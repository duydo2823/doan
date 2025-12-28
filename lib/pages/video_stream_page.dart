import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;

import '../services/rosbridge_client.dart';

// Sửa IP/PORT ROS cho đúng máy của bạn
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

/// Giữ lại hàm normalize cũ để tương thích JSON detections realtime (nếu node video của bạn dùng key 'cls')
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

class _JpegFrame {
  final Uint8List jpeg;
  final int w;
  final int h;
  const _JpegFrame(this.jpeg, this.w, this.h);
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

  CameraController? _cam;
  bool _cameraReady = false;

  // Throttle gửi frame (giảm để YOLO kịp chạy)
  bool _sending = false;
  DateTime? _lastSent;
  final Duration _minInterval = const Duration(milliseconds: 220);

  // Frame jpeg cuối cùng (CHÍNH frame đã gửi ROS) -> hiển thị trên UI
  Uint8List? _lastFrameJpeg;
  int _frameW = 0;
  int _frameH = 0;

  // Detections ổn định (giữ lại vài nhịp nếu YOLO miss)
  Map<String, dynamic>? _stableDetections;
  int _missingCount = 0;
  final int _maxMissingHold = 3;

  // Tối ưu băng thông: giảm kích thước ảnh gửi mà vẫn giữ tỉ lệ (0 = giữ nguyên)
  static const int _maxSendWidth = 960;

  // request id cho video frame (để publishJpeg có frameId)
  int _vidReq = 0;

  @override
  void initState() {
    super.initState();

    _ros = RosbridgeClient(
      url: 'ws://$ROS_IP:$ROSBRIDGE_PORT',
      onStatus: (s) {
        if (!mounted) return;
        setState(() => _status = s);
      },

      // Realtime page này đang vẽ bbox từ JSON detections lên đúng frame đã gửi,
      // nên annotated image có/không không ảnh hưởng. Nhưng callback phải đúng chữ ký:
      onAnnotatedImage: (_, __) {},

      // Chữ ký mới: (Map, requestId)
      onDetections: (m, __) {
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

        // Debug nhanh size (nếu ROS gửi)
        final img = norm['image'];
        if (img is Map) {
          final w = img['width'];
          final h = img['height'];
          debugPrint('DET(image)=$w x $h | FRAME=$_frameW x $_frameH');
        }

        if (mounted) setState(() {});
      },

      onAnnotatedFrame: null,
    );

    _initAll();
  }

  Future<void> _initAll() async {
    await _ros.connect();
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

      // Ưu tiên camera sau
      final back =
      cams.where((c) => c.lensDirection == CameraLensDirection.back).toList();
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
      final converted =
      _cameraImageToJpegKeepAspect(image, maxWidth: _maxSendWidth);
      if (converted == null) return;

      final jpeg = converted.jpeg;
      final w = converted.w;
      final h = converted.h;

      // lưu frame để HIỂN THỊ trên UI (cùng hệ với bbox)
      _lastFrameJpeg = jpeg;
      _frameW = w;
      _frameH = h;

      // gửi ROS (chữ ký mới cần frameId)
      _vidReq++;
      final frameId = 'vid_$_vidReq';
      _ros.publishJpeg(jpeg, frameId: frameId);

      if (mounted) setState(() {});
    } finally {
      _sending = false;
    }
  }

  /// Convert BGRA8888 CameraImage -> JPEG, GIỮ TỈ LỆ.
  /// - Có xử lý stride/bytesPerRow để tránh méo ảnh ngầm.
  /// - Có thể downscale theo maxWidth (giữ tỉ lệ) để giảm load.
  _JpegFrame? _cameraImageToJpegKeepAspect(
      CameraImage image, {
        required int maxWidth,
      }) {
    try {
      final w = image.width;
      final h = image.height;

      final plane = image.planes[0];
      final bytes = plane.bytes;
      final bytesPerRow = plane.bytesPerRow;

      // Tạo ảnh và copy pixel theo stride
      final img = imglib.Image(width: w, height: h);
      for (int y = 0; y < h; y++) {
        final rowStart = y * bytesPerRow;
        for (int x = 0; x < w; x++) {
          final i = rowStart + x * 4;
          final b = bytes[i];
          final g = bytes[i + 1];
          final r = bytes[i + 2];
          final a = bytes[i + 3];
          img.setPixelRgba(x, y, r, g, b, a);
        }
      }

      imglib.Image out = img;

      // Downscale (giữ tỉ lệ) nếu cần
      if (maxWidth > 0 && out.width > maxWidth) {
        final newW = maxWidth;
        final newH = (out.height * (maxWidth / out.width)).round();
        out = imglib.copyResize(
          out,
          width: newW,
          height: newH,
          interpolation: imglib.Interpolation.average,
        );
      }

      final jpg = imglib.encodeJpg(out, quality: 85);
      return _JpegFrame(Uint8List.fromList(jpg), out.width, out.height);
    } catch (e) {
      debugPrint('Convert frame error: $e');
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
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_frameW > 0 && _frameH > 0)
                    Text(
                      'FRAME=$_frameW×$_frameH',
                      style: const TextStyle(fontSize: 12),
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
                      // HIỂN THỊ đúng frame đã gửi ROS -> bbox khớp 100%
                      if (_lastFrameJpeg != null)
                        Image.memory(
                          _lastFrameJpeg!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      else
                        const Center(
                          child: Text(
                            'Đang lấy frame...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),

                      if (_stableDetections != null &&
                          _frameW > 0 &&
                          _frameH > 0)
                        CustomPaint(
                          painter: _DetectionPainterCover(
                            detections: _stableDetections!,
                            imgW: _frameW.toDouble(),
                            imgH: _frameH.toDouble(),
                          ),
                        ),
                    ],
                  )
                      : const Center(
                    child: Text('Đang mở camera...',
                        style: TextStyle(color: Colors.white)),
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

/// Vẽ bbox theo kiểu COVER để khớp Image.memory fit=cover.
class _DetectionPainterCover extends CustomPainter {
  final Map<String, dynamic> detections;
  final double imgW;
  final double imgH;

  _DetectionPainterCover({
    required this.detections,
    required this.imgW,
    required this.imgH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dets = detections['detections'];
    if (dets is! List || dets.isEmpty) return;

    final scale = math.max(size.width / imgW, size.height / imgH);
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

      // Realtime detections node của bạn đang dùng key 'bbox' + 'cls' + 'score'
      final bbox = (raw['bbox'] as List?)
          ?.map((e) => (e as num).toDouble())
          .toList();
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
  bool shouldRepaint(covariant _DetectionPainterCover oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.imgW != imgW ||
        oldDelegate.imgH != imgH;
  }
}
