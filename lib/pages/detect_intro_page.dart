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

  // Không match gì thì giữ nguyên (đã trim)
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

  String get _rosUrl => 'ws://$ROS_IP:$ROSBRIDGE_PORT';

  @override
  void initState() {
    super.initState();
    _ros = RosbridgeClient(
      url: _rosUrl,
      onStatus: (s) => setState(() => _status = s),
      onAnnotatedImage: (jpeg) => setState(() => _annotatedBytes = jpeg),
      onDetections: (m) =>
          setState(() => _detections = normalizeDetectionsJson(m)),
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
      _status = 'Đã ngắt kết nối ROS';
    });
  }

  Future<void> _doPing({bool silent = false}) async {
    try {
      final sw = Stopwatch()..start();

      // ping() trả về record (bool, int?)
      final result = await _ros.ping();
      sw.stop();

      final ok = result.$1;
      final rtt = result.$2 ?? sw.elapsedMilliseconds;

      setState(() {
        _lastPingOk = ok;
        _lastRttMs = rtt;
        _status = ok ? 'ROS OK • RTT ${rtt}ms' : 'Ping ROS thất bại';
      });

      if (!silent && mounted) {
        final msg = ok
            ? 'ROS OK • RTT ${rtt}ms'
            : 'Không thể ping ROS';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      setState(() {
        _lastPingOk = false;
        _lastRttMs = null;
        _status = 'Lỗi ping ROS: $e';
      });
    }
  }

  // ================= GỬI ẢNH LÊN ROS =================

  Future<void> _captureAndSend() async {
    if (!_ros.isConnected || !_lastPingOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Chưa kết nối ROS hoặc ROS không phản hồi.')),
      );
      return;
    }

    try {
      final XFile? photo =
      await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
      if (photo == null) return;

      setState(() {
        _captured = photo;
        _annotatedBytes = null;
        _detections = null;
        _status = 'Đang gửi ảnh chụp lên ROS...';
      });

      final bytes = await photo.readAsBytes();
      _ros.publishJpeg(bytes);

      setState(() {
        _status = 'Đã gửi ảnh, chờ kết quả từ ROS...';
      });
    } on PlatformException catch (e) {
      setState(() => _status = 'Không mở camera: ${e.code}');
    } catch (e) {
      setState(() => _status = 'Lỗi chụp ảnh: $e');
    }
  }

  Future<void> _pickFromGalleryAndSend() async {
    if (!_ros.isConnected || !_lastPingOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Chưa kết nối ROS hoặc ROS không phản hồi.')),
      );
      return;
    }

    try {
      final XFile? file =
      await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
      if (file == null) return;

      setState(() {
        _captured = file;
        _annotatedBytes = null;
        _detections = null;
        _status = 'Đang gửi ảnh (gallery) lên ROS...';
      });

      final bytes = await file.readAsBytes();
      _ros.publishJpeg(bytes);

      setState(() {
        _status = 'Đã gửi ảnh gallery, chờ kết quả từ ROS...';
      });
    } catch (e) {
      setState(() => _status = 'Lỗi chọn ảnh: $e');
    }
  }

  // Gửi frame từ video (nếu bạn còn dùng)
  Future<void> _pickVideoAndSendFrames() async {
    if (!_ros.isConnected || !_lastPingOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Chưa kết nối ROS hoặc ROS không phản hồi.')),
      );
      return;
    }

    try {
      final XFile? xv = await _picker.pickVideo(source: ImageSource.gallery);
      if (xv == null) return;

      setState(() {
        _captured = null;
        _annotatedBytes = null;
        _detections = null;
        _status = 'Đang gửi frame từ video lên ROS...';
      });

      final controller = VideoPlayerController.file(File(xv.path));
      await controller.initialize();
      final totalMs = controller.value.duration.inMilliseconds;
      await controller.dispose();

      const int stepMs = 500; // 0.5s / frame
      const int thumbQuality = 80;
      const int maxH = 480;

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
      }
    } catch (e) {
      setState(() => _status = 'Lỗi đọc/gửi video: $e');
    }
  }

  void _openResultPage() {
    if (_captured == null &&
        _annotatedBytes == null &&
        _detections == null) {
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

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    Widget preview;
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
    final canShoot = connected && _lastPingOk;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhận diện bệnh lá cà phê'),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: 'Xem stream real-time',
            onPressed: () {
              Navigator.pushNamed(context, VideoStreamPage.routeName);
            },
          ),
        ],
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
                            Text(
                              _status,
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _lastPingOk
                                  ? 'ROS OK • RTT: ${_lastRttMs ?? '-'}ms'
                                  : 'Chưa ping được ROS',
                              style: TextStyle(
                                fontSize: 12,
                                color: _lastPingOk
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
                            child: const Text(
                              'Ping',
                              style: TextStyle(fontSize: 12),
                            ),
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
                    child: preview,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Nút chức năng: 2 nút bạn muốn giữ
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

              // Nút gửi video (nếu bạn muốn dùng)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: canShoot ? _pickVideoAndSendFrames : null,
                  icon: const Icon(Icons.video_library),
                  label: const Text('Gửi frame từ video'),
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
