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

  final String url; // ví dụ: ws://192.168.1.100:9090
  final StatusCallback onStatus;
  final AnnotatedImageCallback onAnnotatedImage;
  final DetectionsCallback onDetections;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  bool _connected = false;
  final _uuid = const Uuid();

  // topics
  final String publishTopic = '/app/image/compressed';
  final String annotatedTopic = '/app/annotated/compressed';
  final String detectionsTopic = '/app/detections';

  // quản lý pending service calls
  final Map<String, Completer<Map<String, dynamic>>> _svcWaiters = {};

  Future<void> connect() async {
    if (_connected) return;
    try {
      onStatus('Connecting to $url ...');
      _ch = WebSocketChannel.connect(Uri.parse(url));
      _sub = _ch!.stream.listen(_onMessage,
          onError: (e) => onStatus('WS error: $e'),
          onDone: () {
            _connected = false;
            onStatus('Disconnected');
          });

      await Future<void>.delayed(const Duration(milliseconds: 200));
      _connected = true;
      onStatus('Connected');

      _advertiseCompressedImage(publishTopic);
      _subscribe(annotatedTopic);
      _subscribe(detectionsTopic);
    } catch (e) {
      _connected = false;
      onStatus('Connect failed: $e');
      rethrow;
    }
  }

  void disconnect() {
    _connected = false;
    try {
      _unadvertise(publishTopic);
      _unsubscribe(annotatedTopic);
      _unsubscribe(detectionsTopic);
    } catch (_) {}
    _sub?.cancel();
    _ch?.sink.close();
    _sub = null;
    _ch = null;

    // fail all pending service calls
    for (final c in _svcWaiters.values) {
      if (!c.isCompleted) c.completeError('Disconnected');
    }
    _svcWaiters.clear();
  }

  bool get isConnected => _connected;

  /// Gửi JPEG theo sensor_msgs/CompressedImage (format=jpeg, data=base64)
  void publishJpeg(Uint8List jpegBytes) {
    if (!_connected || _ch == null) {
      onStatus('Not connected; drop frame');
      return;
    }
    final b64 = base64Encode(jpegBytes);
    final payload = {
      'op': 'publish',
      'topic': publishTopic,
      'msg': {'format': 'jpeg', 'data': b64},
    };
    _send(payload);
    onStatus('Frame sent: ${jpegBytes.length} bytes');
  }

  // ---------- PING: call_service /rosapi/get_time ----------
  /// Trả về (ok, roundTripMs). ok=false nếu timeout / lỗi.
  Future<(bool ok, int? roundTripMs)> ping({Duration timeout = const Duration(seconds: 2)}) async {
    if (!_connected || _ch == null) return (false, null);
    final id = _uuid.v4();
    final c = Completer<Map<String, dynamic>>();
    _svcWaiters[id] = c;

    final t0 = DateTime.now().millisecondsSinceEpoch;
    _send({
      'op': 'call_service',
      'id': id,
      'service': '/rosapi/get_time',
      'args': {}, // không cần args
    });

    try {
      final resp = await c.future.timeout(timeout);
      // rosbridge trả: {op: 'service_response', id: <id>, service: '/rosapi/get_time', values: { ... }, result: true}
      final result = (resp['result'] == true);
      final t1 = DateTime.now().millisecondsSinceEpoch;
      return (result, t1 - t0);
    } catch (_) {
      return (false, null);
    } finally {
      _svcWaiters.remove(id);
    }
  }

  // ---------- rosbridge helpers ----------
  void _advertiseCompressedImage(String topic) {
    _send({
      'op': 'advertise',
      'id': _uuid.v4(),
      'topic': topic,
      'type': 'sensor_msgs/CompressedImage',
    });
  }

  void _unadvertise(String topic) {
    _send({'op': 'unadvertise', 'id': _uuid.v4(), 'topic': topic});
  }

  void _subscribe(String topic) {
    _send({'op': 'subscribe', 'id': _uuid.v4(), 'topic': topic});
  }

  void _unsubscribe(String topic) {
    _send({'op': 'unsubscribe', 'id': _uuid.v4(), 'topic': topic});
  }

  void _send(Map<String, dynamic> jsonMsg) {
    if (_ch == null) return;
    _ch!.sink.add(jsonEncode(jsonMsg));
  }

  void _onMessage(dynamic data) {
    try {
      final obj = jsonDecode(data as String) as Map<String, dynamic>;

      // 1) service response (cho ping & các call_service khác)
      if (obj['op'] == 'service_response' && obj['id'] is String) {
        final id = obj['id'] as String;
        final waiter = _svcWaiters[id];
        if (waiter != null && !waiter.isCompleted) {
          waiter.complete(obj);
        }
        return;
      }

      // 2) publish message
      if (obj['op'] == 'publish' && obj.containsKey('topic')) {
        final topic = obj['topic'] as String;
        final msg = obj['msg'];

        if (topic == annotatedTopic && msg is Map) {
          final dataB64 = msg['data'] as String?;
          if (dataB64 != null) {
            final bytes = base64Decode(dataB64);
            onAnnotatedImage(bytes);
          }
        } else if (topic == detectionsTopic) {
          if (msg is Map && msg.containsKey('data')) {
            final dataStr = msg['data']?.toString() ?? '{}';
            try {
              final m = jsonDecode(dataStr) as Map<String, dynamic>;
              onDetections(m);
            } catch (_) {
              onDetections({'raw': dataStr});
            }
          } else if (msg is Map<String, dynamic>) {
            onDetections(msg);
          } else {
            onDetections({'raw': msg});
          }
        }
      }
    } catch (e) {
      onStatus('Parse message error: $e');
    }
  }
}
