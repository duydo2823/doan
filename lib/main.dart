// lib/pages/camera_page.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/rosbridge_client.dart';

// Dùng chung IP / PORT với DetectIntroPage
const String ROS_IP = '172.16.0.237';
const int ROSBRIDGE_PORT = 9090;

const Map<String, String> kDiseaseVI = {
  'Cercospora': 'Đốm mắt cua (Cercospora)',
  'Miner': 'Sâu đục lá (Leaf miner)',
  'Phoma': 'Đốm lá/Thán thư (Phoma)',
  'Rust': 'Rỉ sắt lá (Rust)',
  'Healthy': 'Lá khoẻ mạnh',
};

class CameraPage extends StatefulWidget {
  static const routeName = '/camera-stream';

  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late final RosbridgeClient _ros;

  CameraController? _controller;
  bool _cameraReady = false;

  bool _sending = false; // đang gửi frame lên ROS
  bool _paused = false;  // tạm dừng gửi (preview vẫn chạy)
  double _fps = 1;       // frame/giây gửi lên ROS
  Timer? _timer;

  Uint8List? _annotatedBytes;
  Map<String, dynamic>? _detections;
  int _totalBytes = 0;

  String _status = 'Disconnected';
  bool _lastPingOk = false;
  int? _lastRttMs;
  Timer? _hb;

  String get _rosUrl => 'ws://$ROS_IP:$ROSBRIDGE_PORT';

  @override
  void initState() {
    super.initState();
    _ros = RosbridgeClient(
      url: _rosUrl,
      onStatus: (s) => setState(() => _status = s),
      onAnnotatedImage: (jpeg) => setState(() => _annotatedBytes = jpeg),
      onDetections: (m) => setState(() => _detections = m),
    );
    _connectRos();
  }

  @override
  void dispose() {
    _stopTimer();
    _stopHeartbeat();
    _ros.disconnect();
    _controller?.dispose();
    super.dispose();
  }

  // ========== ROS ==========
  void _startHeartbeat() {
    _hb?.cancel();
    _hb = Timer.periodic(const Duration(seconds: 5), (_) => _doPing(silent: true));
  }

  void _stopHeartbeat() {
    _hb?.cancel();
    _hb = null;
  }

  Future<void> _connectRos() async {
    try {
      await _ros.connect();
      _startHeartbeat();
      await _doPing();
    } catch (_) {}
  }

  Future<void> _doPing({bool silent = false}) async {
    final (ok, rtt) = await _ros.ping();
    setState(() {
      _lastPingOk = ok;
      _lastRttMs = rtt;
    });
    if (!silent) {
      final msg = ok ? 'ROS OK • RTT ${rtt}ms' : 'Không thể ping ROS';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  // ========== CAMERA ==========
  Future<void> _startCamera() async {
    if (!_ros.isConnected || !_lastPingOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa kết nối ROS hoặc ROS không phản hồi.')),
      );
      return;
    }

    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();

      setState(() {
        _controller = controller;
        _cameraReady = true;
        _annotatedBytes = null;
        _detections = null;
        _totalBytes = 0;
      });

      _startSendingFrames();
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Lỗi mở camera: $e');
      }
    }
  }

  void _stopCamera() {
    _stopTimer();
    _controller?.dispose();
    _controller = null;
    setState(() {
      _cameraReady = false;
      _sending = false;
      _paused = false;
    });
  }

  void _startSendingFrames() {
    _stopTimer();
    if (_controller == null || !_controller!.value.isInitialized) return;

    final intervalMs = (1000 / _fps).round();
    _sending = true;
    _paused = false;

    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) async {
      if (_paused || !_sending) return;
      try {
        final file = await _controller!.takePicture();
        final bytes = await File(file.path).readAsBytes();
        _ros.publishJpeg(bytes);
        _totalBytes += bytes.length;
      } catch (_) {}
    });

    setState(() {});
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
  }

  void _onFpsChanged(double value) {
    setState(() => _fps = value);
    if (_sending) {
      _startSendingFrames();
    }
  }

  // ========== UI ==========
  @override
  Widget build(BuildContext context) {
    final connected = _ros.isConnected;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF43A047),
        foregroundColor: Colors.white,
        title: const Text('Stream camera real-time'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 12,
                  color: connected && _lastPingOk ? Colors.lightGreenAccent : Colors.redAccent,
                ),
                const SizedBox(width: 6),
                Text(
                  connected ? (_lastPingOk ? 'Online' : 'No ping') : 'Offline',
                  style: const TextStyle(fontSize: 12),
                ),
                if (_lastRttMs != null) ...[
                  const SizedBox(width: 6),
                  Text('${_lastRttMs}ms', style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF4F8F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Frame sent: $_totalBytes bytes',
                style: const TextStyle(color: Colors.black87),
              ),
              const SizedBox(height: 8),

              // Hàng nút điều khiển camera & ping
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.power_settings_new),
                      label: Text(connected ? 'Đã kết nối' : 'Kết nối'),
                      onPressed: connected ? null : _connectRos,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.link_off),
                      label: const Text('Ngắt'),
                      onPressed: connected ? () => _ros.disconnect() : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.wifi_tethering),
                      label: const Text('Ping'),
                      onPressed: connected ? _doPing : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Nút chụp/thay frame riêng lẻ (nếu muốn dùng lại)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: Icon(_cameraReady ? Icons.stop : Icons.videocam),
                      label: Text(_cameraReady ? 'Dừng Camera' : 'Bắt đầu Camera'),
                      onPressed: _cameraReady ? _stopCamera : _startCamera,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                      label: Text(_paused ? 'Tiếp tục gửi' : 'Tạm dừng gửi'),
                      onPressed: _cameraReady && _sending ? _togglePause : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),
              Text('FPS gửi ROS: ${_fps.toStringAsFixed(1)} fps'),
              Slider(
                value: _fps,
                min: 0.5,
                max: 5,
                divisions: 9,
                label: _fps.toStringAsFixed(1),
                onChanged: _cameraReady ? _onFpsChanged : null,
              ),

              const SizedBox(height: 8),

              // Preview + overlay bbox
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (!_cameraReady || _controller == null) {
                        return const Center(
                          child: Text(
                            'Bấm "Bắt đầu Camera" để mở stream real-time',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      final boxes =
                      (_detections != null && _detections!['detections'] is List)
                          ? List<Map<String, dynamic>>.from(_detections!['detections'])
                          : const <Map<String, dynamic>>[];

                      final imgW = (_detections?['image']?['width'] as num?)?.toDouble();
                      final imgH = (_detections?['image']?['height'] as num?)?.toDouble();

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(_controller!),
                          if (imgW != null && imgH != null && boxes.isNotEmpty)
                            CustomPaint(
                              painter: _StreamBoxesPainter(
                                boxes: boxes,
                                imageW: imgW,
                                imageH: imgH,
                                label: (m) {
                                  final cls = (m['cls'] ?? '').toString();
                                  final vi = kDiseaseVI[cls] ?? cls;
                                  final score =
                                  (m['score'] is num) ? (m['score'] as num).toDouble() : 0.0;
                                  return '${vi.split('(').first.trim()} ${score.toStringAsFixed(2)}';
                                },
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Ảnh annotated nhỏ bên dưới (nếu muốn so sánh)
              if (_annotatedBytes != null)
                SizedBox(
                  height: 100,
                  child: Center(
                    child: Image.memory(_annotatedBytes!),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Painter cho stream (scale theo kích thước preview)
class _StreamBoxesPainter extends CustomPainter {
  _StreamBoxesPainter({
    required this.boxes,
    required this.imageW,
    required this.imageH,
    required this.label,
  });

  final List<Map<String, dynamic>> boxes;
  final double imageW, imageH;
  final String Function(Map<String, dynamic>) label;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / imageW;
    final scaleY = size.height / imageH;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF00BCD4);

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xAA00BCD4);

    for (final m in boxes) {
      final bb = (m['bbox'] as List?)?.map((e) => (e as num).toDouble()).toList();
      if (bb == null || bb.length < 4) continue;

      final left = bb[0] * scaleX;
      final top = bb[1] * scaleY;
      final right = bb[2] * scaleX;
      final bottom = bb[3] * scaleY;

      final rect = Rect.fromLTRB(left, top, right, bottom);
      canvas.drawRect(rect, stroke);

      final textSpan = TextSpan(
        text: label(m),
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      tp.layout();
      const pad = 4.0;
      final labelRect = Rect.fromLTWH(
        rect.left,
        rect.top - (tp.height + pad * 2),
        tp.width + pad * 2,
        tp.height + pad * 2,
      );
      canvas.drawRect(labelRect, fill);
      tp.paint(canvas, Offset(labelRect.left + pad, labelRect.top + pad));
    }
  }

  @override
  bool shouldRepaint(covariant _StreamBoxesPainter old) =>
      old.boxes != boxes || old.imageW != imageW || old.imageH != imageH;
}
