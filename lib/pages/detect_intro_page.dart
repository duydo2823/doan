// lib/pages/detect_intro_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

// Video file → stream từng frame JPEG (dùng cho video từ album)
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

// WebRTC real-time camera
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/rosbridge_client.dart';
import 'result_page.dart';
import 'video_stream_page.dart';

// ====== Cấu hình mạng ======
const String ROS_IP = '192.168.1.251'; // ⚠️ ĐỔI IP MÁY ROS
const int ROSBRIDGE_PORT = 9090;
const int SIGNALING_PORT = 8765;

// ====== Map tên bệnh tiếng Việt ======
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
  // Image picker
  final ImagePicker _picker = ImagePicker();

  // ROS bridge
  late final RosbridgeClient _ros;
  String _status = 'Disconnected';
  bool _lastPingOk = false;
  int? _lastRttMs;
  Timer? _hb;

  // Dữ liệu hiển thị
  XFile? _captured; // ảnh gốc vừa chụp/chọn
  Uint8List? _annotatedBytes; // ảnh annotated ROS trả về
  Map<String, dynamic>? _detections; // JSON detections từ ROS

  // Stream video từ file (album)
  bool _isStreamingVideo = false;

  // WebRTC (real-time)
  RTCPeerConnection? _pc;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  WebSocketChannel? _sig;
  bool _webrtcOn = false;

  // WebRTC real-time (không auto start trên trang này — stream chính nằm ở VideoStreamPage)
  final bool _autoStartWebRTC = false;

  // ✅ Luôn bật hiển thị ảnh annotate (không cho tắt trên UI)
  final bool _showAnnotatedReturn = true;

  String get _rosUrl => 'ws://$ROS_IP:$ROSBRIDGE_PORT';
  String get _signalUrl => 'ws://$ROS_IP:$SIGNALING_PORT';

  // ---------- Lifecycle ----------
  @override
  void initState() {
    super.initState();
    _initRenderers();
    _ros = RosbridgeClient(
      url: _rosUrl,
      onStatus: (s) => setState(() => _status = s),
      onAnnotatedImage: (jpeg) => setState(() => _annotatedBytes = jpeg),
      onDetections: (m) => setState(() => _detections = m),
    );
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize(); // tránh khung trắng khi hiển thị RTCVideoView
  }

  @override
  void dispose() {
    _stopHeartbeat();
    _ros.disconnect();
    _stopWebRTC();
    _localRenderer.dispose();
    super.dispose();
  }

  // ---------- ROS heartbeat ----------
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

      // Trước đây auto start WebRTC ở đây, giờ tắt vì stream ở trang VideoStreamPage
      if (_autoStartWebRTC && !_webrtcOn) {
        _startWebRTC();
      }
    } catch (_) {}
  }

  void _disconnect() {
    _stopHeartbeat();
    _ros.disconnect();
    _stopWebRTC();
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

  // ---------- Ảnh: chụp / chọn & gửi ----------
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

  // ---------- Video file: stream từng frame (album) ----------
  // (Chức năng này hiện đã được thay bằng trang stream realtime, nhưng vẫn giữ code nếu sau này cần lại)
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
        _isStreamingVideo = true;
        _status = 'Đang gửi frame từ video...';
      });

      final totalMs = dur.inMilliseconds;
      const stepMs = 80; // ~12.5 fps
      const thumbQuality = 70;
      const maxH = 720;

      for (int t = 0; t < totalMs; t += stepMs) {
        if (!_isStreamingVideo) break;
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
          _isStreamingVideo = false;
          _status = 'Đã gửi xong frame từ video';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi xong các frame từ video.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isStreamingVideo = false;
          _status = 'Lỗi xử lý video: $e';
        });
      }
    }
  }

  void _stopVideoStream() {
    setState(() {
      _isStreamingVideo = false;
    });
  }

  // ---------- WebRTC real-time ----------
  Future<void> _startWebRTC() async {
    try {
      final media = await navigator.mediaDevices.getUserMedia({
        'video': {
          'facingMode': 'environment',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 24},
        },
        'audio': false,
      });

      _localRenderer.srcObject = media;

      _pc = await createPeerConnection({'sdpSemantics': 'unified-plan'});
      for (final t in media.getTracks()) {
        await _pc!.addTrack(t, media);
      }

      _sig = WebSocketChannel.connect(Uri.parse(_signalUrl));
      _sig!.stream.listen((raw) async {
        try {
          final data = jsonDecode(raw as String);
          if (data['role'] == 'ros' && data['type'] == 'answer') {
            final answer = RTCSessionDescription(data['sdp'], 'answer');
            await _pc!.setRemoteDescription(answer);
            if (mounted) {
              setState(() {
                _webrtcOn = true;
                _status = 'Đang stream & nhận diện...';
              });
            }
          }
        } catch (_) {}
      });

      final offer = await _pc!.createOffer({'offerToReceiveVideo': false});
      await _pc!.setLocalDescription(offer);

      _sig!.sink.add(jsonEncode({
        'role': 'flutter',
        'type': 'offer',
        'sdp': offer.sdp,
      }));

      if (mounted) {
        setState(() {
          _webrtcOn = true;
          _status = 'Đang stream & nhận diện...';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _webrtcOn = false;
        _status = 'WebRTC lỗi: $e';
      });
    }
  }

  void _stopWebRTC() {
    try {
      _pc?.close();
    } catch (_) {}
    try {
      _localRenderer.srcObject?.dispose();
      _localRenderer.srcObject = null;
    } catch (_) {}
    try {
      _sig?.sink.close();
    } catch (_) {}

    setState(() {
      _webrtcOn = false;
    });
  }

  // ---------- Điều hướng kết quả ----------
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
                                connected ? 'Đã kết nối ROSBridge' : 'Chưa kết nối ROSBridge',
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
                                    color: _lastPingOk ? Colors.green.shade700 : Colors.red.shade700,
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
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                minimumSize: Size.zero,
                              ),
                              onPressed: connected ? _disconnect : _connect,
                            ),
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.wifi_tethering, size: 16),
                              label: const Text(
                                'Ping',
                                style: TextStyle(fontSize: 12),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding:
                                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                        '2. Chụp ảnh hoặc chọn ảnh lá cà phê.\n'
                        '3. Bấm "Xem kết quả chi tiết" để xem bounding box và tên bệnh.\n'
                        '4. Nếu muốn nhận diện liên tục theo video, hãy bấm "Mở camera stream".',
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
                          backgroundColor:
                          canShoot ? const Color(0xFF43A047) : Colors.grey,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: canShoot ? _pickFromGalleryAndSend : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // ---- Mở trang stream video real-time ----
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
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
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // ---- WebRTC real-time stream (KHÔNG HIỆN CÔNG TẮC) ----
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'WebRTC (real-time camera → ROS)',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      AspectRatio(
                        aspectRatio: 3 / 4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(color: const Color(0xFFF3F5F7)),

                              // Nền là video WebRTC
                              if (_webrtcOn)
                                RTCVideoView(
                                  _localRenderer,
                                  objectFit: RTCVideoViewObjectFit
                                      .RTCVideoViewObjectFitContain,
                                  mirror: false,
                                ),

                              // ✅ Luôn phủ ảnh annotated khi có (đè lên video)
                              if (_showAnnotatedReturn && _annotatedBytes != null)
                                Image.memory(_annotatedBytes!, fit: BoxFit.contain),

                              if (!_webrtcOn && _annotatedBytes == null)
                                const Center(
                                  child: Text(
                                    'Chưa có dữ liệu • Chụp/chọn ảnh hoặc mở trang stream để nhận diện real-time',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Nút xem kết quả
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
