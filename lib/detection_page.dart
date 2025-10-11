import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Đổi IP theo máy ROS của bạn
const String ROS_URL = 'ws://172.20.10.3:9090';

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
  Uint8List? _annotatedJpeg; // ảnh annotated trả về từ ROS
  Uint8List? _lastCaptured;  // ảnh gốc vừa chụp
  bool _sending = false;

  /// Danh sách bệnh phát hiện được ở frame hiện tại (lowercase, unique)
  final Set<String> _detectedDiseases = {};

  // Quản lý timer để hủy khi dispose
  Timer? _initTimer;
  Timer? _reconnectTimer;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _reconnectTimer?.cancel();
    _initTimer?.cancel();
    _ch?.sink.close();
    super.dispose();
  }

  void _connect() {
    _status = 'Connecting...';
    if (mounted) setState(() {});

    try {
      _ch = WebSocketChannel.connect(Uri.parse(ROS_URL));
    } catch (e) {
      _connected = false;
      _status = 'WS connect error: $e';
      if (mounted) setState(() {});
      _scheduleReconnect();
      return;
    }

    _ch!.stream.listen(
          (event) => _onMessage(event),
      onDone: () {
        _connected = false;
        _status = 'Closed';
        if (mounted) setState(() {});
        _scheduleReconnect();
      },
      onError: (e) {
        _connected = false;
        _status = 'WS error: $e';
        if (mounted) setState(() {});
        _scheduleReconnect();
      },
      cancelOnError: false,
    );

    // đợi 200ms rồi advertise/subscribe
    _initTimer?.cancel();
    _initTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _connected = true;
      _status = 'WS opened';
      setState(() {});
      _advertiseAndSubscribe();
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      _connect();
    });
  }

  void _advertiseAndSubscribe() {
    // ROS 2 type (ROS1 thì dùng: sensor_msgs/CompressedImage)
    _send({
      "op": "advertise",
      "topic": "/app/image/compressed",
      "type": "sensor_msgs/msg/CompressedImage"
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
        _timeoutTimer?.cancel(); // có phản hồi thì hủy timeout
        if (!mounted) return;
        setState(() {
          _resultText = pretty;
          _sending = false;
          _status = 'Detections received';
        });
      } else if (topic == '/app/annotated/compressed') {
        final b64 = obj['msg']?['data'];
        if (b64 is String) {
          final bytes = base64Decode(b64);
          _timeoutTimer?.cancel();
          if (!mounted) return;
          setState(() {
            _annotatedJpeg = bytes;
            _status = 'Annotated image received';
            _sending = false;
          });
        }
      }
    } catch (e) {
      _status = 'Parse err: $e';
      if (mounted) setState(() {});
    }
  }

  // --- Helper: chuyển chuỗi Python-dict thành JSON hợp lệ ---
  String _pythonishToJson(String s) {
    var t = s.replaceAll("'", '"');
    t = t.replaceAllMapped(RegExp(r'\bTrue\b'), (_) => 'true');
    t = t.replaceAllMapped(RegExp(r'\bFalse\b'), (_) => 'false');
    t = t.replaceAllMapped(RegExp(r'\bNone\b|null\b'), (_) => 'null');
    return t;
  }

  /// Parse JSON (chịu lỗi) từ ROS và cập nhật _detectedDiseases
  String _prettyDetections(String jsonString) {
    _detectedDiseases.clear(); // reset mỗi lần nhận kết quả mới
    Map<String, dynamic>? parsed;

    // 1) Thử JSON chuẩn
    try {
      final o = jsonDecode(jsonString);
      if (o is Map<String, dynamic>) parsed = o;
    } catch (_) {}

    // 2) Nếu fail, thử chuyển ' → "'
    if (parsed == null) {
      try {
        final fixed = _pythonishToJson(jsonString);
        final o = jsonDecode(fixed);
        if (o is Map<String, dynamic>) parsed = o;
      } catch (_) {}
    }

    // 3) Nếu vẫn chưa parse được → fallback regex (gom tất cả cls/score)
    if (parsed == null) {
      final reg = RegExp(
        r'''cls['"]?\s*:\s*['"]([^'"}]+)['"].*?score['"]?\s*:\s*([0-9]*\.?[0-9]+)''',
        caseSensitive: false,
        dotAll: true,
      );

      final matches = reg.allMatches(jsonString).toList();
      final buf = StringBuffer('Detections:\n');

      if (matches.isEmpty) {
        _detectedDiseases.add('healthy');
        buf.writeln('No disease detected');
        return buf.toString();
      }

      for (final m in matches) {
        final clsRaw = (m.group(1) ?? '').trim();
        final sc = double.tryParse(m.group(2) ?? '') ?? 0.0;
        final cls = clsRaw.toLowerCase().replaceAll(' ', '_');
        _detectedDiseases.add(cls);
        buf.writeln('- $clsRaw  ${sc.toStringAsFixed(2)}');
      }
      return buf.toString();
    }

    // 4) Luồng parse JSON/đã fixed thành công
    final List dets = (parsed['detections'] as List?) ?? [];
    final num lat =
    (parsed['latency_ms'] is num) ? parsed['latency_ms'] as num : 0;

    final buf = StringBuffer('Detections (${lat.toStringAsFixed(0)} ms):\n');

    if (dets.isEmpty) {
      _detectedDiseases.add('healthy');
      buf.writeln('No disease detected');
      return buf.toString();
    }

    for (final d in dets) {
      final nameRaw = d['cls'].toString();
      final score = (d['score'] as num?)?.toDouble() ?? 0.0;
      final key = nameRaw.toLowerCase().replaceAll(' ', '_');
      _detectedDiseases.add(key);
      buf.writeln('- $nameRaw  ${score.toStringAsFixed(2)}');
    }

    return buf.toString();
  }

  Future<void> _takePhotoAndSend() async {
    if (!_connected) {
      if (mounted) setState(() => _status = 'Not connected to ROS');
      return;
    }

    final picker = ImagePicker();
    final XFile? file =
    await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    _lastCaptured = bytes; // lưu ảnh gốc
    final b64 = base64Encode(bytes);

    final pub = {
      "op": "publish",
      "topic": "/app/image/compressed",
      "msg": {"format": "jpeg", "data": b64}
    };
    _send(pub);

    if (!mounted) return;
    setState(() {
      _sending = true;
      _status = 'Frame sent: ${bytes.length} bytes';
      _resultText = 'Waiting for result...';
      _annotatedJpeg = null;
      _detectedDiseases.clear();
    });

    // timeout 5s
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (_sending) {
        setState(() {
          _sending = false;
          _status = 'Timeout: no response from ROS';
        });
      }
    });
  }

  void _openSolutions() {
    if (_detectedDiseases.isEmpty) return;

    final img = _annotatedJpeg ?? _lastCaptured;
    if (img == null) {
      // chưa có ảnh (chưa chụp xong) -> không mở trang kết quả
      setState(() {
        _status = 'Chưa có ảnh. Vui lòng chụp ảnh trước.';
      });
      return;
    }

    Navigator.pushNamed(
      context,
      '/solution',
      arguments: {
        'diseases': _detectedDiseases.toList(),
        'image': img,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final img = _annotatedJpeg ?? _lastCaptured;
    final canOpen = _detectedDiseases.isNotEmpty && (img != null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Phát hiện bệnh lá cà phê'),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text(_status)),
                const SizedBox(width: 8),
                _sending
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(),
                )
                    : const SizedBox.shrink(),
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
              onPressed: canOpen ? _openSolutions : null,
              icon: const Icon(Icons.medical_information),
              label: const Text('Xem các bệnh đã nhận diện'),
            ),
          ],
        ),
      ),
    );
  }
}
