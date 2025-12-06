import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;

import '../services/rosbridge_client.dart';
import 'result_page.dart';

// Địa chỉ ROS
const String ROS_IP = '172.20.10.3';
const int ROSBRIDGE_PORT = 9090;

/// Chuẩn hoá tên lớp bệnh từ ROS về key chuẩn để app dùng thống nhất
String normalizeDiseaseKey(String raw) {
  final s = raw.trim();
  final lower = s.toLowerCase();

  if (lower.contains('cercospora')) return 'Cercospora';
  if (lower.contains('miner')) return 'Miner';
  if (lower.contains('phoma')) return 'Phoma';
  if (lower.contains('rust')) return 'Rust';
  if (lower.contains('healthy') || lower.contains('normal')) return 'Healthy';

  // Không match gì thì giữ nguyên (đã trim)
  return s;
}

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

  // Kích thước frame nguồn (để scale bbox)
  int? _srcWidth;
  int? _srcHeight;

  // Dữ liệu nhận lại
  Uint8List? _annotatedBytes;           // ảnh ROS vẽ bbox sẵn
  Map<String, dynamic>? _detections;    // JSON bbox (nếu có)

  /// Chuẩn hoá trường 'cls' trong detections_json để ResultPage dùng luôn
  Map<String, dynamic> _normalizeDetections(Map<String, dynamic> src) {
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
      onDetections: (m) =>
          setState(() => _detections = _normalizeDetections(m)),
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
          _status = 'Không tìm thấy camera.';
        });
        return;
      }

      final camera = cameras.first;

      _cameraController = CameraController(
        camera,
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
    if (_cameraController == null || _isStreaming) return;

    _isStreaming = true;
    _lastSent = DateTime.now();

    _cameraController!.startImageStream((image) {
      _srcWidth = image.width;
      _srcHeight = image.height;

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
          setState(() {
            _status = 'Lỗi gửi frame: $e';
          });
        }
      } finally {
        _sendingFrame = false;
      }
    });
  }

  Future<void> _stopImageStream() async {
    if (_cameraController == null || !_isStreaming) return;
    try {
      await _cameraController!.stopImageStream();
    } catch (_) {}
    _isStreaming = false;
  }

  Uint8List? _convertCameraImageToJpeg(CameraImage image) {
    try {
      // BGRA8888 -> Image
      final width = image.width;
      final height = image.height;

      final bgra = image.planes[0].bytes;
      final img = imglib.Image.fromBytes(
        width: width,
        height: height,
        bytes: bgra.buffer,
        order: imglib.ChannelOrder.bgra,
      );

      final jpeg = imglib.encodeJpg(img, quality: 85);
      return Uint8List.fromList(jpeg);
    } catch (e) {
      if (kDebugMode) {
        print('Lỗi convert CameraImage -> JPEG: $e');
      }
      return null;
    }
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
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              if (_detections == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Chưa có kết quả nhận diện từ ROS.')),
                );
                return;
              }
              Navigator.pushNamed(
                context,
                ResultPage.routeName,
                arguments: {
                  'rawPath': null,
                  'annotated': _annotatedBytes,
                  'detections': _detections,
                  'latencyMs': _detections?['latency_ms'],
                },
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _status,
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: Colors.black,
                    child: hasFrame
                        ? LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final h = constraints.maxHeight;

                        Widget base;
                        if (_annotatedBytes != null) {
                          base = Image.memory(
                            _annotatedBytes!,
                            fit: BoxFit.contain,
                            width: w,
                            height: h,
                          );
                        } else if (_cameraController != null &&
                            _cameraController!.value.isInitialized) {
                          base = CameraPreview(_cameraController!);
                        } else {
                          base = const Center(
                            child: Text(
                              'Đang mở camera...',
                              style: TextStyle(color: Colors.white),
                            ),
                          );
                        }

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            base,
                            if (_detections != null &&
                                _srcWidth != null &&
                                _srcHeight != null)
                              CustomPaint(
                                painter: _DetectionPainter(
                                  detections: _detections!,
                                  srcWidth: _srcWidth!,
                                  srcHeight: _srcHeight!,
                                ),
                              ),
                          ],
                        );
                      },
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
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _rosConnected ? 'ROS: Connected' : 'ROS: Disconnected',
                    style: TextStyle(
                      color: _rosConnected ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    _cameraReady ? 'Camera: OK' : 'Camera: ...',
                    style: TextStyle(
                      color: _cameraReady ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
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

class _DetectionPainter extends CustomPainter {
  final Map<String, dynamic> detections;
  final int srcWidth;
  final int srcHeight;

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

    final paintRect = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.greenAccent;

    final paintBg = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.black.withOpacity(0.6);

    for (final raw in dets) {
      final m = Map<String, dynamic>.from(raw as Map);
      final bbox =
      (m['bbox'] as List?)?.map((e) => (e as num).toDouble()).toList();
      if (bbox == null || bbox.length != 4) continue;

      final cls = (m['cls'] ?? '').toString();
      final score =
      (m['score'] is num) ? (m['score'] as num).toDouble() : 0.0;

      final x1 = bbox[0] * scaleX;
      final y1 = bbox[1] * scaleY;
      final x2 = bbox[2] * scaleX;
      final y2 = bbox[3] * scaleY;

      final rect = Rect.fromLTRB(x1, y1, x2, y2);
      canvas.drawRect(rect, paintRect);

      final label =
          '${cls.isEmpty ? 'Object' : cls} ${(score * 100).toStringAsFixed(1)}%';

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: size.width);

      final labelRect = Rect.fromLTWH(
        x1,
        y1 - tp.height - 4,
        tp.width + 8,
        tp.height + 4,
      );

      canvas.drawRect(labelRect, paintBg);
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
