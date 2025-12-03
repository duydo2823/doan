import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef StatusCallback = void Function(String status);
typedef AnnotatedImageCallback = void Function(Uint8List jpegBytes);
typedef DetectionsCallback = void Function(Map<String, dynamic> detections);

class RosbridgeClient {
  RosbridgeClient({
    required this.url,
    required this.onStatus,
    required this.onAnnotatedImage,
    required this.onDetections,
  });

  final String url;
  final StatusCallback onStatus;
  final AnnotatedImageCallback onAnnotatedImage;
  final DetectionsCallback onDetections;

  static const String imageTopic = '/app/image/compressed';
  static const String annotatedTopic = '/app/annotated/compressed';
  static const String detectionsTopic = '/app/detections_json';

  final Uuid _uuid = const Uuid();
  WebSocketChannel? _ch;
  bool _connected = false;

  bool get isConnected => _connected;

  // Ping state
  Completer<(bool, int?)>? _pendingPing;
  String? _pingId;
  DateTime? _pingStart;

  Future<void> connect() async {
    if (_connected) return;
    try {
      onStatus('Connecting to $url ...');
      _ch = WebSocketChannel.connect(Uri.parse(url));
      _connected = true;
      onStatus('Connected to $url');
      _listen();

      // Subscribed topics
      _subscribe(annotatedTopic);
      _subscribe(detectionsTopic);
    } catch (e) {
      _connected = false;
      onStatus('Connect error: $e');
      rethrow;
    }
  }

  void disconnect() {
    if (!_connected) return;
    try {
      _unsubscribe(annotatedTopic);
      _unsubscribe(detectionsTopic);
      _ch?.sink.close();
    } catch (_) {}
    _connected = false;
    onStatus('Disconnected');
  }

  /// Ping ROS qua /rosapi/get_time, trả (ok, rttMs?)
  Future<(bool, int?)> ping() async {
    if (!_connected || _ch == null) return (false, null);
    if (_pendingPing != null) {
      // Đang ping trước đó, trả về luôn future cũ
      return _pendingPing!.future;
    }

    _pingId = 'ping-${_uuid.v4()}';
    _pingStart = DateTime.now();
    _pendingPing = Completer<(bool, int?)>();

    _send({
      'op': 'call_service',
      'id': _pingId,
      'service': '/rosapi/get_time',
      'args': {},
    });

    try {
      final result = await _pendingPing!.future
          .timeout(const Duration(seconds: 3), onTimeout: () {
        if (!_pendingPing!.isCompleted) {
          _pendingPing!.complete((false, null));
        }
        return (false, null);
      });
      _pendingPing = null;
      return result;
    } catch (_) {
      _pendingPing = null;
      return (false, null);
    }
  }

  /// Gửi ảnh JPEG (đã nén) lên topic imageTopic
  void publishJpeg(Uint8List jpegBytes) {
    if (!_connected || _ch == null) {
      onStatus('Not connected; drop frame');
      return;
    }
    final b64 = base64Encode(jpegBytes);
    _send({
      'op': 'publish',
      'id': _uuid.v4(),
      'topic': imageTopic,
      'msg': {'format': 'jpeg', 'data': b64},
    });
    // Không log mỗi frame nữa để tránh spam
  }

  // ============ internal ============

  void _subscribe(String topic) {
    _send({
      'op': 'subscribe',
      'id': _uuid.v4(),
      'topic': topic,
    });
  }

  void _unsubscribe(String topic) {
    _send({
      'op': 'unsubscribe',
      'id': _uuid.v4(),
      'topic': topic,
    });
  }

  void _send(Map<String, dynamic> jsonMsg) {
    if (_ch == null) return;
    try {
      _ch!.sink.add(jsonEncode(jsonMsg));
    } catch (e) {
      onStatus('Send error: $e');
    }
  }

  void _listen() {
    _ch!.stream.listen(
          (dynamic raw) {
        try {
          if (raw is! String) return;
          final data = jsonDecode(raw);
          if (data is! Map<String, dynamic>) return;
          _handleMessage(data);
        } catch (e) {
          onStatus('Parse error: $e');
        }
      },
      onDone: () {
        _connected = false;
        onStatus('Connection closed');
      },
      onError: (e) {
        _connected = false;
        onStatus('Connection error: $e');
      },
    );
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final op = msg['op'];
    if (op == 'publish') {
      final topic = msg['topic'] as String?;
      final payload = msg['msg'];

      if (topic == annotatedTopic && payload is Map) {
        final fmt = payload['format'];
        final data = payload['data'];
        if (fmt == 'jpeg' && data is String) {
          try {
            final bytes = base64Decode(data);
            onAnnotatedImage(bytes);
            onStatus('Annotated image received (${bytes.length} bytes)');
          } catch (e) {
            onStatus('Decode annotated image error: $e');
          }
        }
      } else if (topic == detectionsTopic) {
        if (payload is Map<String, dynamic>) {
          onDetections(payload);
          onStatus('Detections map received ✓');
        } else if (payload is Map) {
          onDetections(payload.cast<String, dynamic>());
          onStatus('Detections map received ✓');
        } else {
          onDetections({'raw': payload});
        }
      }
    } else if (op == 'service_response') {
      final id = msg['id'];
      if (id == _pingId && _pendingPing != null) {
        final now = DateTime.now();
        final rtt = _pingStart != null
            ? now.difference(_pingStart!).inMilliseconds
            : null;
        final ok = msg['result'] == true;
        if (!_pendingPing!.isCompleted) {
          _pendingPing!.complete((ok, rtt));
        }
        _pendingPing = null;
        _pingId = null;
        _pingStart = null;
      }
    }
  }
}
