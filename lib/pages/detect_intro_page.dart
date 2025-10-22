import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/rosbridge_client.dart';
import 'result_page.dart';

class DetectIntroPage extends StatefulWidget {
  static const routeName = '/detect-intro';
  const DetectIntroPage({super.key});

  @override
  State<DetectIntroPage> createState() => _DetectIntroPageState();
}

class _DetectIntroPageState extends State<DetectIntroPage> {
  final ImagePicker _picker = ImagePicker();

  // ⚠️ Đổi IP rosbridge theo máy ROS của bạn
  static const _rosUrl = 'ws://172.20.10.3:9090';

  late final RosbridgeClient _ros;
  String _status = 'Disconnected';
  bool _lastPingOk = false;
  int? _lastRttMs;
  Timer? _hb; // heartbeat timer

  XFile? _captured;
  Uint8List? _annotatedBytes;
  Map<String, dynamic>? _detections;

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

  // ---------- ROS connection ----------
  void _startHeartbeat() {
    _hb?.cancel();
    _hb = Timer.periodic(const Duration(seconds: 5), (_) => _doPing(silent: true));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  // ---------- Capture & send ----------
  Future<void> _captureAndSend() async {
    if (!_ros.isConnected || !_lastPingOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa kết nối ROS hoặc ROS không phản hồi.')),
      );
      return;
    }
    try {
      final x = await _picker.pickImage(source: ImageSource.camera);
      if (x == null) return;
      setState(() {
        _captured = x;
        _annotatedBytes = null;
        _detections = null;
      });
      final bytes = await File(x.path).readAsBytes();
      _ros.publishJpeg(bytes);
      setState(() => _status = 'Ảnh đã gửi lên ROS...');
    } on PlatformException catch (e) {
      final denied = e.code.contains('denied');
      setState(() => _status = denied ? 'Permission denied: camera' : 'Camera error: ${e.code}');
    } catch (e) {
      setState(() => _status = 'Không mở được camera: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _ros.isConnected;
    final canShoot = connected && _lastPingOk;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF43A047),
        foregroundColor: Colors.white,
        title: const Text('Phát hiện bệnh lá cà phê'),
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
              Text(_status, style: const TextStyle(color: Colors.black87)),
              const SizedBox(height: 8),

              // ---- Nút Kết nối / Ngắt / Ping ----
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.power_settings_new),
                    label: Text(connected ? 'Đã kết nối' : 'Kết nối'),
                    onPressed: connected ? null : _connect,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.link_off),
                    label: const Text('Ngắt'),
                    onPressed: connected ? _disconnect : null,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Kiểm tra kết nối'),
                    onPressed: connected ? _doPing : null,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ---- Nút chụp & gửi ----
              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: const Text('Chụp & gửi lên ROS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: canShoot ? const Color(0xFF43A047) : Colors.grey,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: const StadiumBorder(),
                ),
                onPressed: canShoot ? _captureAndSend : null,
              ),

              const SizedBox(height: 12),

              // ---- Hiển thị ảnh (annotated hoặc gốc) ----
              Expanded(
                child: Builder(
                  builder: (_) {
                    if (_annotatedBytes != null) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(_annotatedBytes!, fit: BoxFit.contain),
                      );
                    } else if (_captured != null) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(File(_captured!.path), fit: BoxFit.contain),
                      );
                    }
                    return const Center(
                      child: Text('Chưa có ảnh • Kết nối ROS và bấm “Chụp & gửi lên ROS”'),
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),

              // ---- Kết quả JSON ----
              if (_detections != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
                  ),
                  child: Text('Kết quả: $_detections', style: const TextStyle(fontSize: 14)),
                ),
              ],

              // ---- Nút Xem kết quả ----
              FilledButton.icon(
                icon: const Icon(Icons.visibility),
                label: const Text('Xem kết quả'),
                onPressed: () {
                  if (_captured == null && _annotatedBytes == null) {
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
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
