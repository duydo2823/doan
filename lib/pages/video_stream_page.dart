import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;

import '../services/rosbridge_client.dart';
import 'result_page.dart';

// Địa chỉ ROS
const String ROS_IP = '192.168.1.251';
const int ROSBRIDGE_PORT = 9090;

class VideoStreamPage extends StatefulWidget {
  static const routeName = '/video-stream';

  const VideoStreamPage({super.key});

  @override
  State<VideoStreamPage> createState() => _VideoStreamPageState();
}

class _VideoStreamPageState extends State<VideoStreamPage> {
  // ROS
  late final RosbridgeClient _ros;
  String _status = 'Đang khởi tạo...';
  bool _rosConnected = false;

  // Camera
  CameraController? _cameraController;
  bool _cameraReady = false;

  // Stream frame liên tục
  bool _isStreaming = false;
  bool _sendingFrame = false;
  DateTime? _lastSent;
  final Duration _minInterval =
  const Duration(milliseconds: 300); // ~3–4 fps

  // Kích thước gốc frame gửi sang ROS (để scale bbox)
  int? _srcWidth;
  int? _srcHeight;

  // Dữ liệu nhận lại
  Uint8List? _annotatedBytes;                 // vẫn giữ để xem ở trang kết quả
  Map<String, dynamic>? _detections;          // JSON cho bounding box

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    // 1) ROS
    _ros = RosbridgeClient(
      url: 'ws://$ROS_IP:$ROSBRIDGE_PORT',
      onStatus: (s) => setState(() => _status = s),
      onAnnotatedImage: (jpeg) => setState(() => _annotatedBytes = jpeg),
      onDetections: (m) => setState(() => _detections = m),
    );

    try {
      setState(() => _status = 'Đang kết nối ROS...');
      await _ros.connect();
      if (!mounted) return;
      setState(() {
        _rosConnected = true;
        _status = 'Đã kết nối ROS, đang mở camera...';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rosConnected = false;
        _status = 'Không kết nối được ROS: $e';
      });
    }

    // 2) Camera + stream
    await _initCameraAndStream();
  }

  Future<void> _initCameraAndStream() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _cameraReady = false;
          _status = 'Không tìm thấy camera trên thiết bị.';
        });
        return;
      }

      final backCamera = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController?.dispose();
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      if (!mounted) return;
      setState(() {
        _cameraReady = true;
        _status = 'Camera đã sẵn sàng, đang stream & nhận diện...';
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
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (_isStreaming) return;

    setState(() {
      _isStreaming = true;
      _status = 'Đang stream & nhận diện...';
    });

    await controller.startImageStream((CameraImage image) async {
      if (!_isStreaming || !_rosConnected) return;

      final now = DateTime.now();
      if (_lastSent != null &&
          now.difference(_lastSent!) < _minInterval) {
        return;
      }
      if (_sendingFrame) return;

      _lastSent = now;
      _sendingFrame = true;
      try {
        final jpeg = _convertCameraImageToJpeg(image);
        if (jpeg != null) {
          _ros.publishJpeg(jpeg);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _status = 'Lỗi gửi frame: $e');
        }
      } finally {
        _sendingFrame = false;
      }
    });
  }

  Future<void> _stopImageStream() async {
    _isStreaming = false;
    try {
      if (_cameraController?.value.isStreamingImages == true) {
        await _cameraController?.stopImageStream();
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _status = 'Đã dừng stream.';
      });
    }
  }

  // Chuyển CameraImage BGRA -> JPEG
  Uint8List? _convertCameraImageToJpeg(CameraImage image) {
    if (image.format.group != ImageFormatGroup.bgra8888) {
      return null;
    }

    final plane = image.planes[0];
    final bytes = plane.bytes;

    _srcWidth = image.width;
    _srcHeight = image.height;

    final imglib.Image img = imglib.Image.fromBytes(
      bytes: bytes.buffer,
      width: image.width,
      height: image.height,
      numChannels: 4,
      order: imglib.ChannelOrder.bgra,
    );

    return Uint8List.fromList(imglib.encodeJpg(img, quality: 70));
  }

  @override
  void dispose() {
    _stopImageStream();
    _cameraController?.dispose();
    _ros.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasFrame = _cameraReady || _annotatedBytes != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stream camera & nhận diện'),
        actions: [
          Icon(
            _rosConnected ? Icons.cloud_done : Icons.cloud_off,
            color: _rosConnected ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 12),
        ],
      ),
      backgroundColor: const Color(0xFFF4F8F5),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            icon: const Icon(Icons.visibility),
            label: const Text('Xem kết quả chi tiết'),
            onPressed: !hasFrame
                ? null
                : () {
              Navigator.pushNamed(
                context,
                ResultPage.routeName,
                arguments: {
                  'rawPath': null,
                  'annotated': _annotatedBytes,
                  'detections': _detections,
                },
              );
            },
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _status,
                style:
                const TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_cameraReady && _cameraController != null)
                            CameraPreview(_cameraController!)
                          else
                            const Center(
                              child: Text(
                                'Đang khởi tạo camera...\n'
                                    'Nếu quá lâu không hiện, kiểm tra lại quyền Camera.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          // ⛔ KHÔNG vẽ annotated image đè lên video nữa
                          // Chỉ vẽ bounding box dựa trên detections_json
                          if (_detections != null &&
                              _srcWidth != null &&
                              _srcHeight != null)
                            CustomPaint(
                              painter: _DetectionPainter(
                                detections: _detections!,
                                srcWidth: _srcWidth!.toDouble(),
                                srcHeight: _srcHeight!.toDouble(),
                              ),
                              size: size,
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Khởi động lại stream'),
                      onPressed: () async {
                        await _stopImageStream();
                        await _initCameraAndStream();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Dừng stream'),
                      onPressed: _isStreaming ? _stopImageStream : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vẽ bounding box + nhãn bệnh lên video, dùng dữ liệu từ detections_json
class _DetectionPainter extends CustomPainter {
  final Map<String, dynamic> detections;
  final double srcWidth;
  final double srcHeight;

  _DetectionPainter({
    required this.detections,
    required this.srcWidth,
    required this.srcHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dets = detections['detections'];
    if (dets is! List) return;

    final scaleX = size.width / srcWidth;
    final scaleY = size.height / srcHeight;

    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.redAccent;

    final bgPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.redAccent.withOpacity(0.7);

    for (final raw in dets) {
      final m = Map<String, dynamic>.from(raw as Map);
      final bbox =
      (m['bbox'] as List?)?.map((e) => (e as num).toDouble()).toList();
      if (bbox == null || bbox.length != 4) continue;

      final cls = (m['cls'] ?? '').toString();
      final score =
      (m['score'] is num) ? (m['score'] as num).toDouble() : 0.0;

      // bbox: [x1, y1, x2, y2] theo toạ độ gốc
      final x1 = bbox[0] * scaleX;
      final y1 = bbox[1] * scaleY;
      final x2 = bbox[2] * scaleX;
      final y2 = bbox[3] * scaleY;

      final rect = Rect.fromLTRB(x1, y1, x2, y2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        boxPaint,
      );

      final label =
          '${cls.isEmpty ? 'Object' : cls} ${(score * 100).toStringAsFixed(1)}%';

      // Vẽ label: nền đỏ + chữ trắng
      final textSpan = TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

      final labelRect = Rect.fromLTWH(
        x1,
        y1 - tp.height - 4 < 0 ? y1 + 2 : y1 - tp.height - 4,
        tp.width + 8,
        tp.height + 4,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(3)),
        bgPaint,
      );
      tp.paint(
        canvas,
        Offset(labelRect.left + 4, labelRect.top + 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter oldDelegate) {
    return !mapEquals(oldDelegate.detections, detections) ||
        oldDelegate.srcWidth != srcWidth ||
        oldDelegate.srcHeight != srcHeight;
  }
}
