// lib/pages/detect_intro_page.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/rosbridge_client.dart';
import 'result_page.dart';
import 'video_stream_page.dart';

// Địa chỉ ROS (sửa lại IP cho đúng của bạn)
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

  return s;
}

/// Chuẩn hoá trường 'cls' trong detections_json để ResultPage dùng luôn
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

class DetectIntroPage extends StatefulWidget {
  static const routeName = '/detect-intro';

  const DetectIntroPage({super.key});

  @override
  State<DetectIntroPage> createState() => _DetectIntroPageState();
}

class _DetectIntroPageState extends State<DetectIntroPage> {
  final ImagePicker _picker = ImagePicker();

  late final RosbridgeClient _ros;

  String _status = 'Chưa kết nối ROS';
  bool _lastPingOk = false;
  int? _lastRttMs;
  Timer? _hb;

  XFile? _captured;
  Uint8List? _annotatedBytes;
  Map<String, dynamic>? _detections;

  bool _isWarmingUp = false; // ✅ warm-up sau connect
  bool _isSending = false;   // ✅ chống bấm spam gửi

  String get _rosUrl => 'ws://$ROS_IP:$ROSBRIDGE_PORT';

  @override
  void initState() {
    super.initState();
    _ros = RosbridgeClient(
      url: _rosUrl,
      onStatus: (s) => setState(() => _status = s),

      // ✅ Ưu tiên annotated: khi có ảnh annotated thì giữ nó làm preview chính
      onAnnotatedImage: (jpeg) => setState(() => _annotatedBytes = jpeg),

      onDetections: (m) => setState(() => _detections = normalizeDetectionsJson(m)),
    );
  }

  @override
  void dispose() {
    _stopHeartbeat();
    _ros.disconnect();
    super.dispose();
  }

  // ================= ROS CONNECT / PING =================

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
      setState(() {
        _isWarmingUp = true;
        _status = 'Đang kết nối ROS...';
        _lastPingOk = false;
        _lastRttMs = null;
      });

      await _ros.connect();

      // ✅ Warm-up: cho rosbridge/ROS ổn định 1 nhịp trước khi gửi ảnh
      await Future.delayed(const Duration(milliseconds: 250));
      await _doPing(silent: true);

      _startHeartbeat();

      setState(() {
        _isWarmingUp = false;
        _status = _lastPingOk
            ? 'ROS OK • RTT ${_lastRttMs ?? '-'}ms'
            : 'Đã kết nối nhưng chưa ping được ROS';
      });
    } catch (_) {
      setState(() {
        _isWarmingUp = false;
        _status = 'Kết nối ROS thất bại';
      });
    }
  }

  void _disconnect() {
    _stopHeartbeat();
    _ros.disconnect();
    setState(() {
      _isWarmingUp = false;
      _isSending = false;
      _lastPingOk = false;
      _lastRttMs = null;
      _status = 'Đã ngắt kết nối ROS';
    });
  }

  Future<void> _doPing({bool silent = false}) async {
    try {
      final sw = Stopwatch()..start();
      final result = await _ros.ping();
      sw.stop();

      final ok = result.$1;
      final rtt = result.$2 ?? sw.elapsedMilliseconds;

      setState(() {
        _lastPingOk = ok;
        _lastRttMs = ok ? rtt : null;
        _status = ok ? 'ROS OK • RTT ${rtt}ms' : 'Ping ROS thất bại';
      });

      if (!silent && mounted) {
        final msg = ok ? 'ROS OK • RTT ${rtt}ms' : 'Không thể ping ROS';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      setState(() {
        _lastPingOk = false;
        _lastRttMs = null;
        _status = 'Lỗi ping ROS: $e';
      });
    }
  }

  bool get _canSend => _ros.isConnected && _lastPingOk && !_isWarmingUp && !_isSending;

  // ================= GỬI ẢNH LÊN ROS =================

  Future<void> _captureAndSend() async {
    if (!_ros.isConnected || !_lastPingOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa kết nối ROS hoặc ROS không phản hồi.')),
      );
      return;
    }

    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (photo == null) return;

      setState(() {
        _isSending = true;
        _captured = photo;

        // ✅ Ưu tiên annotated: reset annotated để chờ ảnh mới từ ROS
        _annotatedBytes = null;

        _detections = null;
        _status = 'Đang gửi ảnh chụp lên ROS...';
      });

      final bytes = await photo.readAsBytes();

      // ✅ Nếu rosbridge_client.dart đã sửa publishJpeg => Future<void> thì await
      await _ros.publishJpeg(bytes);

      setState(() {
        _status = 'Đã gửi ảnh, chờ kết quả từ ROS...';
      });
    } on PlatformException catch (e) {
      setState(() => _status = 'Không mở camera: ${e.code}');
    } catch (e) {
      setState(() => _status = 'Lỗi chụp ảnh: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
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
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (file == null) return;

      setState(() {
        _isSending = true;
        _captured = file;

        // ✅ Ưu tiên annotated: reset annotated để chờ ảnh mới từ ROS
        _annotatedBytes = null;

        _detections = null;
        _status = 'Đang gửi ảnh (gallery) lên ROS...';
      });

      final bytes = await file.readAsBytes();

      // ✅ FIX: trước bạn không await, giờ await cho đồng bộ + tránh drop
      await _ros.publishJpeg(bytes);

      setState(() {
        _status = 'Đã gửi ảnh gallery, chờ kết quả từ ROS...';
      });
    } catch (e) {
      setState(() => _status = 'Lỗi chọn ảnh: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
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

  void _openStreamPage() {
    Navigator.pushNamed(context, VideoStreamPage.routeName);
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    Widget preview;

    // ✅ Ưu tiên annotated: có annotated thì luôn hiển thị annotated trước
    if (_annotatedBytes != null) {
      preview = Image.memory(_annotatedBytes!, fit: BoxFit.contain);
    } else if (_captured != null) {
      preview = Image.file(File(_captured!.path), fit: BoxFit.contain);
    } else {
      preview = const Center(
        child: Text('Chưa có ảnh, hãy chụp hoặc chọn ảnh để gửi lên ROS.'),
      );
    }

    final connected = _ros.isConnected;
    final canShoot = connected && _lastPingOk && _ros.isRosReady;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhận diện bệnh lá cà phê'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
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
                            Text(_status, style: const TextStyle(fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(
                              _isWarmingUp
                                  ? 'Đang khởi tạo kết nối...'
                                  : (_lastPingOk
                                  ? 'ROS OK • RTT: ${_lastRttMs ?? '-'}ms'
                                  : 'Chưa ping được ROS'),
                              style: TextStyle(
                                fontSize: 12,
                                color: (_isWarmingUp || _lastPingOk)
                                    ? Colors.green
                                    : Colors.redAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          FilledButton(
                            onPressed: connected ? _disconnect : _connect,
                            child: Text(
                              connected ? 'Ngắt' : 'Kết nối',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 4),
                          OutlinedButton(
                            onPressed: connected ? () => _doPing() : null,
                            child: const Text('Ping', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Ảnh preview
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: Colors.black12,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        preview,

                        // overlay nhỏ để thấy đang gửi/warm-up
                        if (_isWarmingUp || _isSending)
                          Container(
                            color: Colors.black26,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 8),
                                  Text(
                                    _isWarmingUp ? 'Đang khởi tạo...' : 'Đang gửi...',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 2 nút giữ nguyên
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canShoot ? _captureAndSend : null,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Chụp & gửi'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canShoot ? _pickFromGalleryAndSend : null,
                      icon: const Icon(Icons.photo),
                      label: const Text('Ảnh gallery'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Stream video
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (connected && _lastPingOk && !_isWarmingUp) ? _openStreamPage : null,
                  icon: const Icon(Icons.videocam),
                  label: const Text('Stream video'),
                ),
              ),

              const SizedBox(height: 12),

              // Nút xem kết quả chi tiết
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.list_alt),
                  label: const Text('Xem kết quả chi tiết'),
                  onPressed: _openResultPage,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
