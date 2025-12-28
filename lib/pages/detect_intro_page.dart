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

String normalizeDiseaseKey(String raw) {
  final s = raw.trim();
  final lower = s.toLowerCase();
  if (lower.contains('cerc')) return 'Cercospora';
  if (lower.contains('miner')) return 'Miner';
  if (lower.contains('phoma')) return 'Phoma';
  if (lower.contains('rust')) return 'Rust';
  if (lower.contains('healthy')) return 'Healthy';
  return raw.trim();
}

class DetectIntroPage extends StatefulWidget {
  const DetectIntroPage({super.key});
  static const routeName = '/detect';

  @override
  State<DetectIntroPage> createState() => _DetectIntroPageState();
}

class _DetectIntroPageState extends State<DetectIntroPage> {
  final ImagePicker _picker = ImagePicker();
  late final RosbridgeClient _ros;

  String get _rosUrl => 'ws://$ROS_IP:$ROSBRIDGE_PORT';

  String _status = 'Chưa kết nối ROS';
  bool _lastPingOk = false;
  int? _lastRttMs;
  Timer? _hb;

  XFile? _captured;
  Uint8List? _annotatedBytes;
  Map<String, dynamic>? _detections;

  // ====== TRIỆT ĐỂ: match theo request-id ======
  int _reqId = 0;
  String? _activeFrameId;

  bool _waitingAnnotated = false;
  Timer? _annotatedTimeout;

  @override
  void initState() {
    super.initState();

    _ros = RosbridgeClient(
      url: _rosUrl,
      onStatus: (s) {
        if (!mounted) return;
        setState(() => _status = s);
      },

      // ====== annotated: chỉ nhận khi frameId khớp request đang chờ ======
      onAnnotatedImage: (jpeg, frameId) {
        if (!mounted) return;

        // ignore nếu không khớp (bbox về trễ của request cũ)
        if (_activeFrameId != null && frameId != _activeFrameId) {
          return;
        }

        _annotatedTimeout?.cancel();
        setState(() {
          _annotatedBytes = jpeg;
          _waitingAnnotated = false;
          _status = 'Đã nhận ảnh annotated (bbox).';
        });
      },

      // ====== detections: cũng match request_id ======
      onDetections: (m, requestId) {
        if (!mounted) return;

        if (_activeFrameId != null && requestId != _activeFrameId) {
          return;
        }

        // bạn có thể normalize class_name nếu muốn
        setState(() {
          _detections = m;
        });
      },
    );

    _connect();
  }

  @override
  void dispose() {
    _stopHeartbeat();
    _annotatedTimeout?.cancel();
    _ros.disconnect();
    super.dispose();
  }

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

      // Warm-up rosbridge ổn định (giảm “lần đầu lỡ subscribe”)
      await Future.delayed(const Duration(milliseconds: 350));
      await _doPing(silent: true);
      await Future.delayed(const Duration(milliseconds: 250));
      await _doPing(silent: false);

      _startHeartbeat();
    } catch (_) {}
  }

  void _disconnect() {
    _stopHeartbeat();
    _annotatedTimeout?.cancel();
    _ros.disconnect();
    setState(() {
      _lastPingOk = false;
      _lastRttMs = null;
      _status = 'Đã ngắt kết nối ROS';
      _waitingAnnotated = false;
      _activeFrameId = null;
    });
  }

  Future<void> _doPing({bool silent = false}) async {
    try {
      final (ok, rtt) = await _ros.ping();
      if (!mounted) return;

      setState(() {
        _lastPingOk = ok;
        _lastRttMs = rtt;
        if (!silent) {
          _status = ok ? 'ROS OK (ping ${rtt ?? '-'} ms)' : 'ROS không phản hồi';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lastPingOk = false;
        _lastRttMs = null;
        if (!silent) _status = 'ROS không phản hồi';
      });
    }
  }

  // ====== TRIỆT ĐỂ: chờ annotated theo request-id ======
  void _startWaitAnnotated({required String frameId, required int reqIndex}) {
    _annotatedTimeout?.cancel();

    setState(() {
      _waitingAnnotated = true;
      _activeFrameId = frameId;
    });

    // Lần đầu thường chậm hơn -> timeout lâu hơn
    final timeoutMs = (reqIndex <= 2) ? 6500 : 3500;

    _annotatedTimeout = Timer(Duration(milliseconds: timeoutMs), () {
      if (!mounted) return;
      // Nếu vẫn đang chờ đúng request này thì stop wait (fallback)
      if (_waitingAnnotated && _activeFrameId == frameId) {
        setState(() {
          _waitingAnnotated = false;
          _status =
          'Timeout chờ annotated (${timeoutMs}ms) — tạm hiển thị ảnh gốc, nhưng request vẫn hợp lệ.';
        });
      }
    });
  }

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

      _reqId++;
      final frameId = 'req_$_reqId';

      setState(() {
        _captured = photo;
        _annotatedBytes = null;
        _detections = null;
        _status = 'Đang gửi ảnh chụp lên ROS...';
      });

      _startWaitAnnotated(frameId: frameId, reqIndex: _reqId);

      final bytes = await photo.readAsBytes();
      _ros.publishJpeg(bytes, frameId: frameId);

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

      _reqId++;
      final frameId = 'req_$_reqId';

      setState(() {
        _captured = file;
        _annotatedBytes = null;
        _detections = null;
        _status = 'Đang gửi ảnh thư viện lên ROS...';
      });

      _startWaitAnnotated(frameId: frameId, reqIndex: _reqId);

      final bytes = await file.readAsBytes();
      _ros.publishJpeg(bytes, frameId: frameId);

      setState(() {
        _status = 'Đã gửi ảnh gallery, chờ kết quả từ ROS...';
      });
    } catch (e) {
      setState(() => _status = 'Lỗi chọn ảnh: $e');
    }
  }

  void _openResultPage() {
    if (_waitingAnnotated && _annotatedBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đang xử lý... đợi bbox về rồi hãy mở kết quả.')),
      );
      return;
    }

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
        'request_id': _activeFrameId,
      },
    );
  }

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
    final canShoot = connected && _lastPingOk && !_waitingAnnotated;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhận diện bệnh lá cà phê'),
        actions: [
          IconButton(
            tooltip: 'Xem video realtime',
            icon: const Icon(Icons.videocam),
            onPressed: () {
              Navigator.pushNamed(context, VideoStreamPage.routeName);
            },
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_status),
                            const SizedBox(height: 6),
                            Text(
                              connected
                                  ? (_lastPingOk
                                  ? 'ROS: OK (${_lastRttMs ?? '-'} ms)'
                                  : 'ROS: Không phản hồi')
                                  : 'Chưa kết nối',
                              style: TextStyle(
                                fontSize: 12,
                                color: _lastPingOk ? Colors.green : Colors.redAccent,
                              ),
                            ),
                            if (_activeFrameId != null)
                              Text(
                                'Request: $_activeFrameId',
                                style: const TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          FilledButton(
                            onPressed: connected ? _disconnect : _connect,
                            child: Text(connected ? 'Ngắt' : 'Kết nối'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () => _doPing(silent: false),
                            child: const Text('Ping'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Expanded(
                child: Stack(
                  children: [
                    Center(child: preview),
                    if (_waitingAnnotated)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(0.25),
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 10),
                                Text(
                                  'Đang xử lý ảnh / chờ bbox...',
                                  style: TextStyle(color: Colors.white),
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Chụp ảnh'),
                      onPressed: canShoot ? _captureAndSend : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Chọn ảnh'),
                      onPressed: canShoot ? _pickFromGalleryAndSend : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.list_alt),
                  label: const Text('Xem kết quả chi tiết'),
                  onPressed: (_waitingAnnotated && _annotatedBytes == null)
                      ? null
                      : _openResultPage,
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
