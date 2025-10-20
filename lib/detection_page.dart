// lib/detection_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

/// Đổi theo IP rosbridge của bạn
const String ROS_URL = 'ws://192.168.1.252:9090';

class DetectionPage extends StatefulWidget {
  const DetectionPage({super.key});

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage> {
  WebSocketChannel? _ch;
  bool _connected = false;
  String _status = 'Disconnected';
  String _resultText = '';
  Uint8List? _annotatedJpeg;
  bool _sending = false;

  /// null = chưa có kết quả; 'healthy' = không bệnh; còn lại = tên bệnh
  String? _detectedDisease;

  int _retryMs = 500;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    try {
      _ch?.sink.close();
    } catch (_) {}
    _ch = null;
    super.dispose();
  }

  // ================== WS ===================
  void _connect() {
    _status = 'Connecting...';
    if (mounted) setState(() {});

    try {
      _ch = WebSocketChannel.connect(Uri.parse(ROS_URL));
    } catch (e) {
      _scheduleReconnect('Connect error: $e');
      return;
    }

    _ch!.stream.listen(
          (event) => _onMessage(event),
      onDone: () => _scheduleReconnect('Closed'),
      onError: (e) => _scheduleReconnect('WS error: $e'),
      cancelOnError: false,
    );

    // đợi 200ms rồi advertise/subscribe
    Future.delayed(const Duration(milliseconds: 200), () {
      _connected = true;
      _status = 'WS opened';
      if (mounted) setState(() {});
      _retryMs = 500;
      _advertiseAndSubscribe();
    });
  }

  void _scheduleReconnect(String reason) {
    _connected = false;
    _status = reason;
    if (mounted) setState(() {});
    _ch = null;

    final delay = Duration(milliseconds: _retryMs.clamp(500, 5000));
    _retryMs = (_retryMs * 2).clamp(500, 5000);
    Future.delayed(delay, () {
      if (mounted) _connect();
    });
  }

  void _advertiseAndSubscribe() {
    _send({
      "op": "advertise",
      "topic": "/app/image/compressed",
      "type": "sensor_msgs/msg/CompressedImage",
    });

    _send({"op": "subscribe", "topic": "/app/detections_json"});
    _send({"op": "subscribe", "topic": "/app/annotated/compressed"});
  }

  void _send(Object jsonObj) {
    try {
      _ch?.sink.add(jsonEncode(jsonObj));
    } catch (e) {
      _status = 'Send err: $e';
      if (mounted) setState(() {});
    }
  }

  void _onMessage(dynamic text) {
    try {
      final obj = jsonDecode(text as String);
      final topic = obj['topic'] ?? '';

      if (topic == '/app/detections_json') {
        final data = obj['msg']?['data'] ?? '{}';
        final pretty = _prettyDetections(data.toString());
        _sending = false;
        if (mounted) {
          setState(() {
            _resultText = pretty;
            _status = 'Detections received';
          });
        }
      } else if (topic == '/app/annotated/compressed') {
        final b64 = obj['msg']?['data'];
        if (b64 is String) {
          final jpeg = base64Decode(b64);
          if (mounted) {
            setState(() {
              _annotatedJpeg = jpeg;
              _status = 'Annotated image received';
            });
          }
        }
        _sending = false;
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Parse err: $e');
      }
    }
  }

  // ============= Parse detections JSON =============
  String _prettyDetections(String jsonString) {
    try {
      final o = jsonDecode(jsonString);

      // kỳ vọng: { detections: [ {cls: "...", score: 0.9}, ... ], latency_ms: 42 }
      final List dets = (o['detections'] as List?) ?? [];
      final double lat = (o['latency_ms'] ?? 0).toDouble();

      final buf = StringBuffer('Detections (${lat.toStringAsFixed(0)} ms):\n');

      if (dets.isEmpty) {
        if (mounted) {
          _detectedDisease = 'healthy';
        }
        buf.writeln('No disease detected');
      } else {
        dets.sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));
        final top = dets.first;
        final name = top['cls'].toString();
        // final score = (top['score'] as num).toStringAsFixed(2);

        if (mounted) {
          _detectedDisease = name;
        }

        for (final d in dets) {
          buf.writeln('- ${d["cls"]}  ${(d["score"] as num).toStringAsFixed(2)}');
        }
      }
      return buf.toString();
    } catch (_) {
      return jsonString;
    }
  }

  // ============= Permissions + capture =============
  Future<bool> _ensurePermissions() async {
    final statuses = await [Permission.camera].request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<void> _takePhotoAndSend() async {
    if (!_connected) {
      if (mounted) setState(() => _status = 'Not connected to ROS');
      return;
    }

    // xin quyền trước khi mở camera
    final ok = await _ensurePermissions();
    if (!ok) {
      if (mounted) setState(() => _status = 'Permission denied: camera');
      return;
    }

    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);

      final pub = {
        "op": "publish",
        "topic": "/app/image/compressed",
        "msg": {"format": "jpeg", "data": b64}
      };
      _send(pub);

      if (mounted) {
        setState(() {
          _sending = true;
          _status = 'Frame sent: ${bytes.length} bytes';
          _resultText = 'Waiting for result...';
          _annotatedJpeg = null;
          _detectedDisease = null;
        });
      }

      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _sending) {
          setState(() {
            _sending = false;
            _status = 'Timeout: no response from ROS';
          });
        }
      });
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _status = 'Camera error: ${e.code}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Unexpected error: $e');
      }
    }
  }

  // ================== UI ===================
  @override
  Widget build(BuildContext context) {
    final img = _annotatedJpeg;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Phát hiện bệnh lá cà phê'),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            tooltip: 'Xem giải pháp',
            onPressed: _detectedDisease == null
                ? null
                : () {
              Navigator.pushNamed(
                context,
                '/solution',
                arguments: {'disease': _detectedDisease},
              );
            },
            icon: const Icon(Icons.health_and_safety),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text(_status)),
                const SizedBox(width: 8),
                _sending ? const SizedBox(
                  height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ) : const SizedBox.shrink(),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _takePhotoAndSend,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Chụp & gửi lên ROS'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (img != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(img),
                      ),
                    const SizedBox(height: 8),
                    SelectableText(_resultText),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _detectedDisease == null
                  ? null
                  : () {
                Navigator.pushNamed(
                  context,
                  '/solution',
                  arguments: {'disease': _detectedDisease},
                );
              },
              icon: const Icon(Icons.medical_information),
              label: const Text('Xem giải pháp'),
            ),
          ],
        ),
      ),
    );
  }
}
