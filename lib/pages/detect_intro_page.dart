// lib/pages/detect_intro_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/rosbridge_client.dart';
import 'result_page.dart';

const String ROS_IP = '172.20.10.3';
const int ROSBRIDGE_PORT = 9090;
const int SIGNALING_PORT = 8765;

const Map<String, String> kDiseaseVI = {
  'Cercospora': 'Đốm mắt cua (Cercospora)',
  'Miner': 'Sâu đục lá (Leaf miner)',
  'Phoma': 'Thán thư (Phoma)',
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
  bool _isStreamingVideo = false;

  RTCPeerConnection? _pc;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  WebSocketChannel? _sig;
  bool _webrtcOn = false;
  bool _showAnnotatedReturn = false;

  String get _rosUrl => 'ws://$ROS_IP:$ROSBRIDGE_PORT';
  String get _signalUrl => 'ws://$ROS_IP:$SIGNALING_PORT';

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
    await _localRenderer.initialize();
  }

  @override
  void dispose() {
    _stopHeartbeat();
    _ros.disconnect();
    _stopWebRTC();
    _localRenderer.dispose();
    super.dispose();
  }

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _captureAndSend() async {
    if (!_ros.isConnected || !_lastPingOk) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Chưa kết nối ROS hoặc ROS không phản hồi.')));
      return;
    }
    try {
      final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1280);
      if (x == null) return;
      setState(() {
        _captured = x;
        _annotatedBytes = null;
        _detections = null;
      });
      final bytes = await File(x.path).readAsBytes();
      _ros.publishJpeg(bytes);
    } catch (e) {
      setState(() => _status = 'Lỗi camera: $e');
    }
  }

  Future<void> _pickFromGalleryAndSend() async {
    if (!_ros.isConnected || !_lastPingOk) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Chưa kết nối ROS hoặc ROS không phản hồi.')));
      return;
    }
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1280);
      if (x == null) return;
      setState(() {
        _captured = x;
        _annotatedBytes = null;
        _detections = null;
      });
      final bytes = await File(x.path).readAsBytes();
      _ros.publishJpeg(bytes);
    } catch (e) {
      setState(() => _status = 'Lỗi chọn ảnh: $e');
    }
  }

  Future<void> _pickVideoAndStreamFrames() async {
    if (!_ros.isConnected || !_lastPingOk) return;
    try {
      final xv = await _picker.pickVideo(source: ImageSource.gallery);
      if (xv == null) return;
      final file = File(xv.path);
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      final dur = controller.value.duration;
      await controller.dispose();

      setState(() {
        _isStreamingVideo = true;
        _status = 'Đang gửi frame từ video...';
      });

      for (int t = 0; t <= dur.inMilliseconds; t += 400) {
        if (!_isStreamingVideo) break;
        final bytes = await VideoThumbnail.thumbnailData(
          video: xv.path,
          timeMs: t,
          imageFormat: ImageFormat.JPEG,
          quality: 75,
          maxHeight: 720,
        );
        if (bytes != null) _ros.publishJpeg(bytes);
        await Future.delayed(const Duration(milliseconds: 30));
      }
      setState(() {
        _isStreamingVideo = false;
        _status = 'Đã gửi xong video';
      });
    } catch (e) {
      setState(() {
        _isStreamingVideo = false;
        _status = 'Lỗi video: $e';
      });
    }
  }

  void _stopVideoStream() => setState(() => _isStreamingVideo = false);

  Future<void> _startWebRTC() async {
    try {
      final media = await navigator.mediaDevices.getUserMedia({
        'video': {'facingMode': 'environment', 'width': {'ideal': 1280}, 'height': {'ideal': 720}},
        'audio': false,
      });
      _localRenderer.srcObject = media;
      setState(() {});

      _pc = await createPeerConnection({'sdpSemantics': 'unified-plan'});
      for (var t in media.getTracks()) {
        await _pc!.addTrack(t, media);
      }

      _sig = WebSocketChannel.connect(Uri.parse(_signalUrl));
      _sig!.stream.listen((raw) async {
        final data = jsonDecode(raw);
        if (data['role'] == 'ros' && data['type'] == 'answer') {
          final answer = RTCSessionDescription(data['sdp'], 'answer');
          await _pc!.setRemoteDescription(answer);
          setState(() => _webrtcOn = true);
        }
      });

      final offer = await _pc!.createOffer({'offerToReceiveVideo': false});
      await _pc!.setLocalDescription(offer);
      _sig!.sink.add(jsonEncode({'role': 'flutter', 'type': 'offer', 'sdp': offer.sdp}));
      setState(() => _webrtcOn = true);
    } catch (e) {
      setState(() => _status = 'WebRTC lỗi: $e');
    }
  }

  Future<void> _stopWebRTC() async {
    try {
      await _pc?.close();
      await _localRenderer.srcObject?.dispose();
      _localRenderer.srcObject = null;
      await _sig?.sink.close();
    } catch (_) {}
    setState(() => _webrtcOn = false);
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
      ),
      backgroundColor: const Color(0xFFF4F8F5),

      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            icon: const Icon(Icons.visibility),
            label: const Text('Xem kết quả'),
            onPressed: () {
              if (_captured == null && _annotatedBytes == null && _detections == null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Chưa có dữ liệu để hiển thị')));
                return;
              }
              Navigator.pushNamed(context, ResultPage.routeName, arguments: {
                'rawPath': _captured?.path,
                'annotated': _annotatedBytes,
                'detections': _detections,
              });
            },
          ),
        ),
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_status, style: const TextStyle(color: Colors.black87)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
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
              ]),
              const SizedBox(height: 12),

              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Chụp ảnh'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canShoot ? const Color(0xFF43A047) : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: canShoot ? _captureAndSend : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Chọn ảnh'),
                    onPressed: canShoot ? _pickFromGalleryAndSend : null,
                  ),
                ),
              ]),
              const SizedBox(height: 8),

              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.video_library_outlined),
                    label: Text(_isStreamingVideo ? 'Đang gửi video...' : 'Chọn video'),
                    onPressed: (!canShoot || _isStreamingVideo) ? null : _pickVideoAndStreamFrames,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Dừng gửi'),
                    onPressed: _isStreamingVideo ? _stopVideoStream : null,
                  ),
                ),
              ]),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'WebRTC (real-time camera → ROS)',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const Text('Hiện ảnh annotate', style: TextStyle(fontSize: 12)),
                        Switch(
                          value: _showAnnotatedReturn,
                          onChanged: (v) => setState(() => _showAnnotatedReturn = v),
                        ),
                        const SizedBox(width: 8),
                        const Text('Bật', style: TextStyle(fontSize: 12)),
                        Switch(value: _webrtcOn, onChanged: (v) => v ? _startWebRTC() : _stopWebRTC()),
                      ],
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
                            if (_showAnnotatedReturn && _annotatedBytes != null)
                              Image.memory(_annotatedBytes!, fit: BoxFit.contain),
                            if (!_showAnnotatedReturn &&
                                (_annotatedBytes != null || _captured != null))
                              (_annotatedBytes != null)
                                  ? Image.memory(_annotatedBytes!, fit: BoxFit.contain)
                                  : Image.file(File(_captured!.path), fit: BoxFit.contain),
                            if ((_annotatedBytes == null && _captured == null) && _webrtcOn)
                              RTCVideoView(
                                _localRenderer,
                                objectFit:
                                RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                                mirror: false,
                              ),
                            if (!_webrtcOn && _annotatedBytes == null && _captured == null)
                              const Center(
                                child: Text(
                                  'Chưa bật WebRTC • Gạt công tắc “Bật” ở góc phải\nhoặc chụp/chọn ảnh để xem',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.black54),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.play_circle_fill),
                          label: const Text('Start WebRTC'),
                          onPressed: _webrtcOn ? null : _startWebRTC,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop'),
                          onPressed: _webrtcOn ? _stopWebRTC : null,
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
