import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;

import '../services/rosbridge_client.dart';

// ====== SỬA IP CHO ĐÚNG MÁY ROS ======
const String ROS_IP = '172.20.10.3';
const int ROSBRIDGE_PORT = 9090;

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
        final rawCls = (mm['cls'] ?? '').toString();
        mm['cls'] = normalizeDiseaseKey(rawCls);
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

  CameraController? _cameraController;
  bool _cameraReady = false;

  // Throttle gửi frame
  bool _sendingFrame = false;
  DateTime? _lastSent;
  final Duration _minInterval = const Duration(milliseconds: 200);

  // Kích thước ảnh GỬI lên ROS (không xoay)
  int? _sentWidth;
  int? _sentHeight;

  // Detections ổn định (giữ bbox cũ để đỡ chớp)
  Map<String, dynamic>? _stableDetections;
  int _missingCount = 0;
  final int _maxMissingHold = 3;

  @override
  void initState() {
    super.initState();

    _ros = RosbridgeClient(
      url: 'ws://$ROS_IP:$ROSBRIDGE_PORT',
      onStatus: (s) => setState(() => _status = s),
      onAnnotatedImage: (_) {},
      onDetections: (m) {
        final norm = normalizeDetectionsJson(m);
        _updateDetections(norm);

        // Debug: xem JSON trả về size gì
        final img = norm['image'];
        if (img is Map) {
          debugPrint(
              'DET image size: ${img['width']}x${img['height']}  sent=${_sentWidth}x$_sentHeight');
        }
      },
      onAnnotatedFrame: null,
    );

    _initAll();
  }

  void _updateDetections(Map<String, dynamic> det) {
    final list = det['detections'];

    if (list is List && list.isNotEmpty) {
      _stableDetections = det;
      _missingCount = 0;
    } else {
      _missingCount += 1;
      if (_missingCount > _maxMissingHold) {
        _stableDetections = det; // thật sự trống
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> _initAll() async {
    await _ros.connect();
    await _initCameraAndStream();
  }

  Future<void> _initCameraAndStream() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() {
          _cameraReady = false;
          _status = 'Không tìm thấy camera.';
        });
        return;
      }

      final cam = cams.first;
      _cameraController = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() {
        _cameraReady = true;
        _status = 'Camera OK • Đang stream & gửi lên ROS...';
      });

      await _startImageStream();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraReady = false;
        _status = 'Lỗi khởi tạo camera: $e';
      });
    }
  }

  Future<void> _startImageStream() async {
    if (_cameraController == null) return;

    _lastSent = DateTime.now();

    _cameraController!.startImageStream((image) async {
      final now = DateTime.now();
      if (_lastSent != null && now.difference(_lastSent!) < _minInterval) {
        return;
      }
      if (_sendingFrame) return;

      _lastSent = now;
      _sendingFrame = true;
      try {
        final jpeg = _convertCameraImageToJpegNoRotate(image);
        if (jpeg != null) _ros.publishJpeg(jpeg);
      } finally {
        _sendingFrame = false;
      }
    });
  }

  Uint8List? _convertCameraImageToJpegNoRotate(CameraImage image) {
    try {
      final width = image.width;
      final height = image.height;
      final bgra = image.planes[0].bytes;

      final img0 = imglib.Image.fromBytes(
        width: width,
        height: height,
        bytes: bgra.buffer,
        order: imglib.ChannelOrder.bgra,
      );

      // cập nhật kích thước ảnh gửi lên ROS
      _sentWidth = img0.width;
      _sentHeight = img0.height;

      final jpg = imglib.encodeJpg(img0, quality: 85);
      return Uint8List.fromList(jpg);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    try {
      _cameraController?.stopImageStream();
    } catch (_) {}
    _cameraController?.dispose();
    _ros.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _ros.isConnected;

    return Scaffold(
      appBar: AppBar(title: const Text('ROS Video Stream')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Container(
                    padding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      connected ? _status : 'Disconnected',
                      style:
                      const TextStyle(color: Colors.white, fontSize: 12),
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
                      // CameraPreview thực tế là COVER (lấp đầy và crop)
                      CameraPreview(_cameraController!),

                      if (_stableDetections != null &&
                          _sentWidth != null &&
                          _sentHeight != null)
                        CustomPaint(
                          painter: _DetectionPainterCover(
                            detections: _stableDetections!,
                            sentWidth: _sentWidth!,
                            sentHeight: _sentHeight!,
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

/// ✅ Painter dùng COVER mapping (max scale) để khớp CameraPreview
class _DetectionPainterCover extends CustomPainter {
  final Map<String, dynamic> detections;
  final int sentWidth;
  final int sentHeight;

  _DetectionPainterCover({
    required this.detections,
    required this.sentWidth,
    required this.sentHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dets = detections['detections'];
    if (dets is! List || dets.isEmpty) return;

    // Ưu tiên size từ JSON (ROS trả về); fallback sentWidth/sentHeight
    double imgW = sentWidth.toDouble();
    double imgH = sentHeight.toDouble();

    final imgInfo = detections['image'];
    if (imgInfo is Map) {
      final w = imgInfo['width'];
      final h = imgInfo['height'];
      if (w is num && h is num && w > 0 && h > 0) {
        imgW = w.toDouble();
        imgH = h.toDouble();
      }
    }

    // COVER scale (khác contain): max -> lấp đầy, crop mép
    final scale = math.max(size.width / imgW, size.height / imgH);

    // offset sẽ thường âm hoặc dương tùy crop
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

      final bbox =
      (raw['bbox'] as List?)?.map((e) => (e as num).toDouble()).toList();
      if (bbox == null || bbox.length != 4) continue;

      final cls = (raw['cls'] ?? '').toString();
      final score =
      (raw['score'] is num) ? (raw['score'] as num).toDouble() : 0.0;

      final x1 = bbox[0] * scale + offsetX;
      final y1 = bbox[1] * scale + offsetY;
      final x2 = bbox[2] * scale + offsetX;
      final y2 = bbox[3] * scale + offsetY;

      canvas.drawRect(Rect.fromLTRB(x1, y1, x2, y2), rectPaint);

      final text = '$cls ${(score * 100).toStringAsFixed(1)}%';

      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
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
  bool shouldRepaint(covariant _DetectionPainterCover oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.sentWidth != sentWidth ||
        oldDelegate.sentHeight != sentHeight;
  }
}
