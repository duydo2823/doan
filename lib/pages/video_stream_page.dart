// lib/pages/video_stream_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/rosbridge_client.dart';
import 'result_page.dart';

// ====== Cấu hình mạng (giữ giống DetectIntroPage) ======
const String ROS_IP = '192.168.1.251'; // ⚠️ Đổi IP nếu máy ROS đổi IP
const int ROSBRIDGE_PORT = 9090;
const int SIGNALING_PORT = 8765;

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

  // WebRTC
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  WebSocketChannel? _sigChannel;
  bool _webrtcOn = false;

  // Kết quả nhận diện
  Uint8List? _annotatedBytes;
  Map<String, dynamic>? _detections;

  String get _rosUrl => 'ws://$ROS_IP:$ROSBRIDGE_PORT';
  String get _signalUrl => 'ws://$ROS_IP:$SIGNALING_PORT';

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    await _localRenderer.initialize();

    _ros = RosbridgeClient(
      url: _rosUrl,
      onStatus: (s) => setState(() => _status = s),
      onAnnotatedImage: (jpeg) => setState(() => _annotatedBytes = jpeg),
      onDetections: (m) => setState(() => _detections = m),
    );

    try {
      await _ros.connect();
      if (!mounted) return;
      setState(() {
        _rosConnected = true;
        _status = 'Đã kết nối ROS, đang bật WebRTC...';
      });
      await _startWebRTC();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rosConnected = false;
        _status = 'Không kết nối được ROS: $e';
      });
    }
  }

  // ====== WebRTC ======
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
      for (final track in media.getTracks()) {
        await _pc!.addTrack(track, media);
      }

      _sigChannel = WebSocketChannel.connect(Uri.parse(_signalUrl));
      _sigChannel!.stream.listen((raw) async {
        try {
          final data = jsonDecode(raw as String);
          if (data is Map &&
              data['role'] == 'ros' &&
              data['type'] == 'answer') {
            final answer =
            RTCSessionDescription(data['sdp'] as String, 'answer');
            await _pc?.setRemoteDescription(answer);
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

      _sigChannel!.sink.add(jsonEncode({
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

  Future<void> _stopWebRTC() async {
    try {
      await _pc?.close();
    } catch (_) {}
    try {
      await _localRenderer.srcObject?.dispose();
      _localRenderer.srcObject = null;
    } catch (_) {}
    try {
      await _sigChannel?.sink.close();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _webrtcOn = false;
        _status = 'Đã dừng stream.';
      });
    }
  }

  @override
  void dispose() {
    _stopWebRTC();
    _ros.disconnect();
    _localRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasFrame = _annotatedBytes != null || _webrtcOn;

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
                      if (_webrtcOn)
                        RTCVideoView(
                          _localRenderer,
                          objectFit: RTCVideoViewObjectFit
                              .RTCVideoViewObjectFitContain,
                          mirror: false,
                        ),
                      if (_annotatedBytes != null)
                        Image.memory(_annotatedBytes!, fit: BoxFit.contain),
                      if (!_webrtcOn && _annotatedBytes == null)
                        const Center(
                          child: Text('Đang khởi tạo WebRTC...'),
                        ),
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
                        await _stopWebRTC();
                        await _startWebRTC();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Dừng stream'),
                      onPressed: _webrtcOn ? _stopWebRTC : null,
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
