import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/rosbridge_client.dart';
import 'result_page.dart';

// 🔹 Giữ nguyên camera code của bạn ở đây

class DetectionPage extends StatefulWidget {
  const DetectionPage({super.key});

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage> {
  // ---- ROS Bridge config ----
  static const _rosUrl = 'ws://172.20.10.3:9090';
  late final RosbridgeClient _ros;
  String _status = 'Disconnected';
  bool _lastPingOk = false;
  int? _lastRttMs;
  Timer? _hb;

  Uint8List? _annotatedBytes;
  Map<String, dynamic>? _detections;
  String? _lastCapturedPath;

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
    _hb?.cancel();
    _ros.disconnect();
    super.dispose();
  }

  void _startHeartbeat() {
    _hb?.cancel();
    _hb = Timer.periodic(const Duration(seconds: 5), (_) => _doPing(silent: true));
  }

  Future<void> _connect() async {
    try {
      await _ros.connect();
      _startHeartbeat();
      await _doPing();
    } catch (_) {}
  }

  void _disconnect() {
    _hb?.cancel();
    _hb = null;
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
    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'ROS OK • RTT ${rtt}ms' : 'Không thể ping ROS')),
      );
    }
  }

  // 🔸 Gửi ảnh chụp lên ROS
  Future<void> _sendCapturedFile(String filePath) async {
    try {
      _lastCapturedPath = filePath;
      _annotatedBytes = null;
      _detections = null;
      final bytes = await File(filePath).readAsBytes();
      _ros.publishJpeg(bytes);
      setState(() {});
    } on PlatformException catch (e) {
      setState(() => _status = 'Camera error: ${e.code}');
    } catch (e) {
      setState(() => _status = 'Không đọc được ảnh: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _ros.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Phát hiện bệnh lá cà phê'),
        backgroundColor: Colors.green,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Icon(Icons.circle,
                    size: 12,
                    color: connected && _lastPingOk
                        ? Colors.lightGreenAccent
                        : Colors.redAccent),
                const SizedBox(width: 6),
                Text(
                  connected
                      ? (_lastPingOk ? 'Online' : 'No ping')
                      : 'Offline',
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

      // 🔹 Giữ nguyên phần CAMERA của bạn ở body — chỉ thêm các phần ROS bên dưới
      body: Column(
        children: [
          // 👉 Camera preview của bạn ở đây
          Expanded(
            child: Container(
              color: Colors.black12,
              alignment: Alignment.center,
              child: const Text('Camera Preview (phần này giữ nguyên của bạn)'),
            ),
          ),

          // 🔹 Nút điều khiển ROS
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
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
          ),

          // 🔹 Ảnh annotate ROS trả về
          if (_annotatedBytes != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_annotatedBytes!, fit: BoxFit.contain),
              ),
            ),

          // 🔹 JSON kết quả ROS
          if (_detections != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text('Kết quả: $_detections'),
              ),
            ),

          // 🔹 Nút xem kết quả
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.icon(
              icon: const Icon(Icons.visibility),
              label: const Text('Xem kết quả'),
              onPressed: (_lastCapturedPath != null || _annotatedBytes != null)
                  ? () {
                Navigator.pushNamed(
                  context,
                  ResultPage.routeName,
                  arguments: {
                    'rawPath': _lastCapturedPath,
                    'annotated': _annotatedBytes,
                    'detections': _detections,
                  },
                );
              }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
