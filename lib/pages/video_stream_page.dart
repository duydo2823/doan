// lib/pages/video_stream_page.dart
//
// ✅ Stream camera -> resize 640x640 -> JPEG -> gửi ROS
// ✅ Nhận detections_json (bbox theo 640x640) -> vẽ overlay KHÔNG LỆCH
// ✅ Giữ bbox cũ vài nhịp để đỡ chớp (hold)
// ✅ Throttle gửi frame để ROS chạy kịp

import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;

import '../services/rosbridge_client.dart';

// ======= SỬA IP/PORT ROS CỦA BẠN Ở ĐÂY =======
const String ROS_IP = '172.20.10.3';
const int ROSBRIDGE_PORT = 9090;

// ======= normalize tên class =======
String normalizeDiseaseKey(String raw) {
  final s = raw.trim();
  final lower = s.toLowerCase();
  if (lower.contains('cercospora')) return 'Cercospora';
  if (lower.contains('miner')) return 'Miner';
  if (lower.contains('phoma')) return 'Phoma';
  if (lower.contains('rust')) return 'Rust';
  if (lower.contains('healthy') || lower.contains('normal')) return 'Healthy';
  return s;
}

Map<String, dynamic> normalizeDetectionsJson(Map<String, dynamic> src) {
  final map = Map<String, dynamic>.from(src);
  final dets = map['detections'];
  if (dets is List) {
    map['detections'] = dets.map((e) {
      if (e is Map) {
        final mm = Map<String, dynamic>.from(e);
        mm['cls'] = normalizeDiseaseKey((mm['cls'] ?? '').toString());
        return mm;
      }
      return e;
    }).toList();
  }
  return map;
}

class VideoStreamPage extends StatefulWidget {
  static const routeName = '/video-stream';
  const VideoStreamPage({super.key});

  @override
  State<VideoStreamPage> createState() => _VideoStreamPageState();
}

class _VideoStreamPageState extends State<VideoStreamPage> {
  late final RosbridgeClient _ros;

  String _status = 'Đang kết nối ROS...';
  bool _connected = false;

  CameraController? _cam;
  bool _cameraReady = false;

  // ======= stream control =======
  bool _sending = false;
  DateTime? _lastSent;
  final Duration _minInterval = const Duration(milliseconds: 220); // 180-300ms tuỳ máy

  // ======= detections =======
  Map<String, dynamic>? _stableDetections;
  int _missingCount = 0;
  final int _maxMissingHold = 3;

  // ======= hard-fixed size =======
  static const int kDetW = 640;
  static const int kDetH = 640;

  @override
  void initState() {
    super.initState();

    _ros = RosbridgeClient(
      url: 'ws://$ROS_IP:$ROSBRIDGE_PORT',
      onStatus: (s) {
        if (!mounted) return;
        setState(() => _status = s);
      },
      onAnnotatedImage: (_) {},
      onDetections: (m) {
        final norm = normalizeDetectionsJson(m);

        final dets = norm['detections'];
        if (dets is List && dets.isNotEmpty) {
          _stableDetections = norm;
          _missingCount = 0;
        } else {
          _missingCount += 1;
          if (_missingCount > _maxMissingHold) {
            _stableDetections = norm; // trống thật
          }
        }

        // debug size (nếu ROS trả image.width/height)
        final img = norm['image'];
        if (img is Map) {
          debugPrint('DET(image)=${img['width']}x${img['height']} (expect 640x640)');
        }

        if (mounted) setState(() {});
      },
      onAnnotatedFrame: null,
    );

    _initAll();
  }

  Future<void> _initAll() async {
    try {
      await _ros.connect();
      if (!mounted) return;
      setState(() => _connected = _ros.isConnected);
    } catch (_) {}

    await _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (!mounted) return;
        setState(() {
          _cameraReady = false;
          _status = 'Không tìm thấy camera.';
        });
        return;
      }

      // ưu tiên camera sau nếu có
      final back = cams.where((c) => c.lensDirection == CameraLensDirection.back).toList();
      final camDesc = back.isNotEmpty ? back.first : cams.first;

      _cam = CameraController(
        camDesc,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );

      await _cam!.initialize();
      if (!mounted) return;

      setState(() {
        _cameraReady = true;
        _status = 'Camera OK • Đang stream & gửi lên ROS...';
      });

      _lastSent = DateTime.now();
      await _cam!.startImageStream(_onFrame);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraReady = false;
        _status = 'Lỗi camera: $e';
      });
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    final now = DateTime.now();
    if (_lastSent != null && now.difference(_lastSent!) < _minInterval) return;
    if (_sending) return;

    _lastSent = now;
    _sending = true;

    try {
      final jpeg = _toJpeg640(image);
      if (jpeg != null) {
        _ros.publishJpeg(jpeg);
      }
    } catch (_) {
      // ignore
    } finally {
      _sending = false;
    }
  }

  /// ✅ Convert BGRA camera image -> imglib.Image -> resize 640x640 -> JPEG
  /// Lưu ý: resize này là "bóp" ảnh (không giữ tỉ lệ) để đồng hệ toạ độ 640x640.
  Uint8List? _toJpeg640(CameraImage image) {
    try {
      final w = image.width;
      final h = image.height;
      final bgra = image.planes[0].bytes;

      final src = imglib.Image.fromBytes(
        width: w,
        height: h,
        bytes: bgra.buffer,
        order: imglib.ChannelOrder.bgra,
      );

      final resized = imglib.copyResize(
        src,
        width: kDetW,
        height: kDetH,
        interpolation: imglib.Interpolation.average,
      );

      final jpg = imglib.encodeJpg(resized, quality: 85);
      return Uint8List.fromList(jpg);
    } catch (e) {
      debugPrint('Resize/JPEG error: $e');
      return null;
    }
  }

  @override
  void dispose() {
    try {
      _cam?.stopImageStream();
    } catch (_) {}
    _cam?.dispose();
    _ros.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _ros.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ROS Video Stream'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // status
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      connected ? _status : 'Disconnected',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.black,
                  child: _cameraReady
                      ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // CameraPreview thường là "cover"
                      // Nhưng bbox ta vẽ theo hệ 640x640 -> ta sẽ tự map theo cover ngay trong painter.
                      CameraPreview(_cam!),

                      if (_stableDetections != null)
                        CustomPaint(
                          painter: _Painter640Cover(
                            detections: _stableDetections!,
                          ),
                        ),
                    ],
                  )
                      : const Center(
                    child: Text(
                      'Đang mở camera...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter: bbox thuộc hệ 640x640, vẽ lên preview theo kiểu COVER để khớp CameraPreview.
class _Painter640Cover extends CustomPainter {
  final Map<String, dynamic> detections;
  _Painter640Cover({required this.detections});

  static const double imgW = 640.0;
  static const double imgH = 640.0;

  @override
  void paint(Canvas canvas, Size size) {
    final dets = detections['detections'];
    if (dets is! List || dets.isEmpty) return;

    // CameraPreview = cover => scale = max
    final scale = (size.width / imgW > size.height / imgH)
        ? (size.width / imgW)
        : (size.height / imgH);

    final offsetX = (size.width - imgW * scale) / 2.0;
    final offsetY = (size.height - imgH * scale) / 2.0;

    final rectPaint = Paint()
      ..color = const Color(0xFF00FF00)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final bgPaint = Paint()
      ..color = const Color(0x88000000)
      ..style = PaintingStyle.fill;

    for (final raw in dets) {
      if (raw is! Map) continue;

      final bbox = (raw['bbox'] as List?)?.map((e) => (e as num).toDouble()).toList();
      if (bbox == null || bbox.length != 4) continue;

      final cls = (raw['cls'] ?? '').toString();
      final score = (raw['score'] is num) ? (raw['score'] as num).toDouble() : 0.0;

      final x1 = bbox[0] * scale + offsetX;
      final y1 = bbox[1] * scale + offsetY;
      final x2 = bbox[2] * scale + offsetX;
      final y2 = bbox[3] * scale + offsetY;

      canvas.drawRect(Rect.fromLTRB(x1, y1, x2, y2), rectPaint);

      final text = '$cls ${(score * 100).toStringAsFixed(1)}%';
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final bg = Rect.fromLTWH(
        x1,
        y1 - tp.height - 4,
        tp.width + 6,
        tp.height + 4,
      );

      canvas.drawRect(bg, bgPaint);
      tp.paint(canvas, Offset(bg.left + 3, bg.top + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _Painter640Cover oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
