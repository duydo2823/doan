import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../services/rosbridge_client.dart';
import 'result_page.dart';
import 'video_stream_page.dart';

// Địa chỉ ROS
const String ROS_IP = '172.20.10.3';
const int ROSBRIDGE_PORT = 9090;

const Map<String, String> kDiseaseVI = {
  'Cercospora': 'Đốm mắt cua (Cercospora)',
  'Miner': 'Sâu đục lá (Leaf miner)',
  'Phoma': 'Đốm lá/Thán thư (Phoma)',
  'Rust': 'Rỉ sắt lá (Rust)',
  'Healthy': 'Lá khoẻ mạnh',
};

class DetectIntroPage extends StatefulWidget {
  static const routeName = '/detect-intro';
  const DetectIntroPage({super.key});

  @override
  State<DetectIntroPage> createState() => _DetectIntroPageState();
}

class _DetectIntroPageState extends State<DetectIntroPage> {
  final ImagePicker _picker = ImagePicker();

  late final RosbridgeClient _ros;
  String _status = 'Disconnected';
  bool _lastPingOk = false;
  int? _lastRttMs;
  Timer? _hb;

  XFile? _captured;
  Uint8List? _annotatedBytes;
  Map<String, dynamic>? _detections;

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
  }

  @override
  void dispose() {
    _stopHeartbeat();
    _ros.disconnect();
    super.dispose();
  }

  // ========= ROS heartbeat & ping =========

  void _startHeartbeat() {
    _hb?.cancel();
    _hb = Timer.periodic(const Duration(seconds: 5), (_) {
      _doPing(silent: true);
    });
  }

  void _stopHeartbeat() {
    _hb?.cancel();
    _hb = null;
  }

  Future<void> _connect() async {
    try {
      await _ros.connect();
      _startHeartbeat();
      await _doPing();
    } catch (_) {}
  }

  void _disconnect() {
    _stopHeartbeat();
    _ros.disconnect();
    setState(() {
      _lastPingOk = false;
      _lastRttMs = null;
    });
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  // ========= GỬI ẢNH TĨNH =========

  Future<void> _captureAndSend() async {
    if (!_ros.isConnected || !_lastPingOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa kết nối ROS hoặc ROS không phản hồi.')),
      );
      return;
    }
    try {
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1280,
      );
      if (x == null) return;

      setState(() {
        _captured = x;
        _annotatedBytes = null;
        _detections = null;
        _status = 'Đang gửi ảnh...';
      });

      final bytes = await File(x.path).readAsBytes();
      _ros.publishJpeg(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi ảnh chụp lên ROS')),
        );
      }
    } on PlatformException catch (e) {
      setState(() => _status = 'Không mở camera: ${e.code}');
    } catch (e) {
      setState(() => _status = 'Lỗi chụp ảnh: $e');
    }
  }

  Future<void> _pickFromGalleryAndSend() async {
    if (!_ros.isConnected || !_lastPingOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa kết nối ROS hoặc ROS không phản hồi.')),
      );
      return;
    }
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1280,
      );
      if (x == null) return;

      setState(() {
        _captured = x;
        _annotatedBytes = null;
        _detections = null;
        _status = 'Đang gửi ảnh từ thư viện...';
      });

      final bytes = await File(x.path).readAsBytes();
      _ros.publishJpeg(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi ảnh từ thư viện lên ROS')),
        );
      }
    } on PlatformException catch (e) {
      setState(() => _status = 'Không mở thư viện ảnh: ${e.code}');
    } catch (e) {
      setState(() => _status = 'Lỗi mở thư viện: $e');
    }
  }

  // (Tuỳ chọn) Stream từng frame từ 1 file video trong gallery – không dùng UI nữa nhưng giữ lại nếu cần
  Future<void> _pickVideoAndStreamFrames() async {
    if (!_ros.isConnected || !_lastPingOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa kết nối ROS hoặc ROS không phản hồi.')),
      );
      return;
    }

    try {
      final xv = await _picker.pickVideo(source: ImageSource.gallery);
      if (xv == null) return;

      final file = File(xv.path);
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      final dur = controller.value.duration;
      await controller.dispose();

      setState(() {
        _captured = null;
        _annotatedBytes = null;
        _detections = null;
        _status = 'Đang gửi frame từ video (gallery)...';
      });

      final totalMs = dur.inMilliseconds;
      const stepMs = 80; // ~12.5 fps
      const thumbQuality = 70;
      const maxH = 720;

      for (int t = 0; t < totalMs; t += stepMs) {
        final bytes = await VideoThumbnail.thumbnailData(
          video: xv.path,
          timeMs: t,
          imageFormat: ImageFormat.JPEG,
          quality: thumbQuality,
          maxHeight: maxH,
        );
        if (bytes == null) continue;
        _ros.publishJpeg(bytes);
        await Future.delayed(const Duration(milliseconds: 20));
      }

      if (mounted) {
        setState(() {
          _status = 'Đã gửi xong frame từ video (gallery)';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi xong các frame từ video.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Lỗi xử lý video: $e';
        });
      }
    }
  }

  void _openResultPage() {
    if (_captured == null && _annotatedBytes == null && _detections == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có dữ liệu để hiển thị')),
      );
      return;
    }
    Navigator.pushNamed(
      context,
      ResultPage.routeName,
      arguments: {
        'rawPath': _captured?.path,
        'annotated': _annotatedBytes,
        'detections': _detections,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = _ros.isConnected;
    final canShoot = connected && _lastPingOk;

    Widget preview;
    if (_annotatedBytes != null) {
      preview = Image.memory(_annotatedBytes!, fit: BoxFit.contain);
    } else if (_captured != null) {
      preview = Image.file(File(_captured!.path), fit: BoxFit.contain);
    } else {
      preview = const Center(
        child: Text(
          'Chưa có ảnh.\nHãy chụp hoặc chọn ảnh, hoặc mở camera stream.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhận diện bệnh lá cà phê'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.pushNamed(context, '/history'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Trạng thái ROS
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          connected ? Icons.cloud_done : Icons.cloud_off,
                          color: connected ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                connected
                                    ? 'Đã kết nối ROSBridge'
                                    : 'Chưa kết nối ROSBridge',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _status,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (_lastRttMs != null)
                                Text(
                                  'Ping ROS: $_lastRttMs ms • ${_lastPingOk ? 'OK' : 'FAIL'}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _lastPingOk
                                        ? Colors.green.shade700
                                        : Colors.red.shade700,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          children: [
                            ElevatedButton.icon(
                              icon: Icon(
                                connected ? Icons.cloud_off : Icons.cloud,
                                size: 18,
                              ),
                              label: Text(connected ? 'Ngắt' : 'Kết nối'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                minimumSize: Size.zero,
                              ),
                              onPressed: connected ? _disconnect : _connect,
                            ),
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              icon:
                              const Icon(Icons.wifi_tethering, size: 16),
                              label: const Text(
                                'Ping',
                                style: TextStyle(fontSize: 12),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                              ),
                              onPressed: connected ? () => _doPing() : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Hướng dẫn
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '1. Kết nối tới ROSBridge.\n'
                        '2. Chụp ảnh hoặc chọn ảnh lá cà phê để nhận diện.\n'
                        '3. Bấm "Xem kết quả chi tiết" để xem bounding box và tên bệnh.\n'
                        '4. Nếu muốn nhận diện liên tục theo video, bấm "Mở camera stream".',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
                const SizedBox(height: 16),

                // Nút chụp / chọn ảnh
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Chụp ảnh'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canShoot
                              ? const Color(0xFF43A047)
                              : Colors.grey,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: canShoot ? _captureAndSend : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Chọn ảnh'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: canShoot ? _pickFromGalleryAndSend : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Nút mở trang stream video
                FilledButton.icon(
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('Mở camera stream'),
                  onPressed: !canShoot
                      ? null
                      : () {
                    Navigator.pushNamed(
                      context,
                      VideoStreamPage.routeName,
                    );
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    shape: const StadiumBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Preview ảnh / annotated
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: preview,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                FilledButton.icon(
                  icon: const Icon(Icons.visibility),
                  label: const Text('Xem kết quả chi tiết'),
                  onPressed: _openResultPage,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
