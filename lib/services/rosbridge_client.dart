import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

class RosbridgeClient {
  final String url;

  final void Function(String status)? onStatus;
  final void Function(Uint8List jpeg)? onAnnotatedImage;
  final void Function(Map<String, dynamic> json)? onDetections;
  final void Function(Uint8List jpeg)? onAnnotatedFrame;

  WebSocketChannel? _socket;
  StreamSubscription? _sub;

  bool get isConnected => _socket != null;

  bool _rosReady = false;
  bool get isRosReady => _rosReady;

  int _idCounter = 0;
  final Map<String, Completer<Map<String, dynamic>>> _pendingService = {};

  RosbridgeClient({
    required this.url,
    this.onStatus,
    this.onAnnotatedImage,
    this.onDetections,
    this.onAnnotatedFrame,
  });

  Future<void> connect() async {
    try {
      onStatus?.call('Connecting to $url ...');
      _rosReady = false;

      _socket = WebSocketChannel.connect(Uri.parse(url));
      onStatus?.call('Connected');

      _sub = _socket!.stream.listen(
        _onMessage,
        onDone: () {
          onStatus?.call('Disconnected');
          _socket = null;
          _rosReady = false;
        },
        onError: (e) {
          onStatus?.call('Error: $e');
          _socket = null;
          _rosReady = false;
        },
      );

      _advertiseAndSubscribe();

      // ✅ Warm-up thật: gọi rosapi để xác nhận ROS stack trả lời được
      final ok = await _probeRosReady();
      _rosReady = ok;

      onStatus?.call(ok ? 'ROS READY' : 'Connected but ROS not ready');
    } catch (e) {
      onStatus?.call('Connection error: $e');
      _socket = null;
      _rosReady = false;
    }
  }

  void disconnect() {
    _sub?.cancel();
    _sub = null;
    _socket?.sink.close();
    _socket = null;
    _rosReady = false;
    onStatus?.call('Disconnected');
  }

  void _sendRaw(Map<String, dynamic> msg) {
    if (_socket == null) return;
    _socket!.sink.add(jsonEncode(msg));
  }

  void _advertiseAndSubscribe() {
    _sendRaw({
      'op': 'advertise',
      'topic': '/app/image/compressed',
      'type': 'sensor_msgs/CompressedImage',
    });

    _sendRaw({
      'op': 'subscribe',
      'topic': '/app/annotated/compressed',
      'type': 'sensor_msgs/CompressedImage',
    });

    _sendRaw({
      'op': 'subscribe',
      'topic': '/app/detections_json',
      'type': 'std_msgs/String',
    });

    _sendRaw({
      'op': 'subscribe',
      'topic': '/video/annotated',
      'type': 'sensor_msgs/CompressedImage',
    });
  }

  /// ✅ “Ping ROS thật” bằng rosapi get_time
  Future<bool> _probeRosReady() async {
    if (_socket == null) return false;

    // nếu rosapi không chạy, bạn sẽ luôn false -> lúc đó cần chạy rosapi node
    try {
      final res = await callService('/rosapi/get_time', {})
          .timeout(const Duration(seconds: 1));
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Call service qua rosbridge (không cần sửa ROS YOLO)
  Future<Map<String, dynamic>> callService(
      String service,
      Map<String, dynamic> args,
      ) async {
    final id = 'srv_${_idCounter++}_${DateTime.now().microsecondsSinceEpoch}';
    final c = Completer<Map<String, dynamic>>();
    _pendingService[id] = c;

    _sendRaw({
      'op': 'call_service',
      'service': service,
      'args': args,
      'id': id,
    });

    return c.future;
  }

  /// Gửi 1 frame JPEG lên topic /app/image/compressed
  Future<void> publishJpeg(Uint8List bytes) async {
    if (_socket == null) return;

    // Nếu ROS chưa ready thì thử probe lại nhanh
    if (!_rosReady) {
      _rosReady = await _probeRosReady();
    }

    final msg = {
      'op': 'publish',
      'topic': '/app/image/compressed',
      'msg': {
        'format': 'jpeg',
        'data': base64Encode(bytes),
      },
    };

    _socket!.sink.add(jsonEncode(msg));
  }

  /// Ping: trả về true khi WebSocket còn và ROS ready
  Future<(bool, int?)> ping() async {
    if (!isConnected) return (false, null);
    if (!_rosReady) {
      _rosReady = await _probeRosReady();
    }
    return (_rosReady, null);
  }

  void _onMessage(dynamic data) {
    try {
      final jsonData = jsonDecode(data);
      if (jsonData is! Map) return;

      final op = jsonData['op'];

      // ✅ Bắt service_response để hoàn tất probe
      if (op == 'service_response') {
        final String? id = jsonData['id'];
        if (id != null && _pendingService.containsKey(id)) {
          final c = _pendingService.remove(id)!;
          c.complete(Map<String, dynamic>.from(jsonData));
        }
        return;
      }

      if (op != 'publish') return;

      final topic = jsonData['topic'];
      final msg = jsonData['msg'];

      if (topic == '/app/annotated/compressed' || topic == '/video/annotated') {
        final String? b64 = msg['data'];
        if (b64 != null) {
          final bytes = base64Decode(b64);
          // DEBUG: print('ANNOTATED len=${bytes.length}');
          onAnnotatedImage?.call(bytes);
          onAnnotatedFrame?.call(bytes);
        }
        return;
      }

      if (topic == '/app/detections_json') {
        final String? s = msg['data'];
        if (s != null) {
          final decoded = jsonDecode(s);
          // DEBUG: print('DETECTIONS msg=$decoded');
          if (decoded is Map<String, dynamic>) {
            onDetections?.call(decoded);
          } else if (decoded is Map) {
            onDetections?.call(
              Map<String, dynamic>.from(decoded as Map<dynamic, dynamic>),
            );
          }
        }
        return;
      }
    } catch (e) {
      onStatus?.call('Parse error: $e');
    }
  }
}
