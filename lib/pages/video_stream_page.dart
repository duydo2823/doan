// lib/pages/video_stream_page.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/rosbridge_client.dart';
import 'result_page.dart';

// ====== Cấu hình mạng (giống DetectIntroPage) ======
const String ROS_IP = '172.20.10.3'; // ⚠️ Đổi IP nếu máy ROS đổi IP
const int ROSBRIDGE_PORT = 9090;

class VideoStreamPage extends StatefulWidget {
  static const routeName = '/video-stream';

  const VideoStreamPage({super.key});

  @override
  State<VideoStreamPage> createState() => _VideoStreamPageState();
}

class _VideoStreamPageState extends State<VideoStreamPage> {
  // ROS bridge
  late final RosbridgeClient _ros;
  String _status = 'Đang khởi tạo...';
  bool _rosConnected = false;

  // Camera
  CameraController? _cameraController;
  bool _cameraReady = false;

  // Gửi frame định kỳ
  Timer? _frameTimer;
  bool _sendingFrame = false;
  Duration _frameInterval = const Duration(milliseconds: 800); // ~1.2 fps

  // Kết quả nhận diện
  Uint8List? _annotatedBytes;
  Map<String, dynamic>? _detections;

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    // 1) Kết nối ROS
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

    // 2) Mở camera
    await _initCamera();
    // 3) Bắt đầu gửi frame
    _startFrameTimer();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _cameraReady = false;
          _status = 'Không tìm thấy camera trên thiết bị.';
        });
        return;
      }

      // Ưu tiên camera sau
      final backCamera = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (!mounted) return;
      setState(() {
        _cameraReady = true;
        _status = 'Camera đã sẵn sàng, đang stream & nhận diện...';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraReady = false;
        _status = 'Lỗi khởi tạo camera: $e';
      });
    }
  }

  void _startFrameTimer() {
    _frameTimer?.cancel();
    if (!_rosConnected || !_cameraReady) return;

    _frameTimer = Timer.periodic(_frameInterval, (_) => _captureAndSendFrame());
  }

  void _stopFrameTimer() {
    _frameTimer?.cancel();
    _frameTimer = null;
  }

  Future<void> _captureAndSendFrame() async {
    if (!_rosConnected || !_cameraReady || _sendingFrame) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      _sendingFrame = true;
      final XFile file = await controller.takePicture();
      final bytes = await file.readAsBytes();

      // Gửi JPEG lên ROS
      _ros.publishJpeg(bytes);
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Lỗi gửi frame: $e');
      }
    } finally {
      _sendingFrame = false;
    }
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _cameraController?.dispose();
    _ros.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasFrame = _annotatedBytes != null || _cameraReady;

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
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Preview camera
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

                      // Ảnh annotated từ ROS (nếu có) đè lên
                      if (_annotatedBytes != null)
                        Image.memory(_annotatedBytes!, fit: BoxFit.contain),
                    ],
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
                        _stopFrameTimer();
                        await _cameraController?.dispose();
                        setState(() {
                          _cameraReady = false;
                          _annotatedBytes = null;
                        });
                        await _initCamera();
                        _startFrameTimer();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Dừng stream'),
                      onPressed: () {
                        _stopFrameTimer();
                        setState(() {
                          _status = 'Đã dừng stream.';
                        });
                      },
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
