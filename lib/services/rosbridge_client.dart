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

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  bool _connected = false;
  final _uuid = const Uuid();

  final String publishTopic = '/app/image/compressed';
  final String annotatedTopic = '/app/annotated/compressed';
  final List<String> detectionTopics = const [
    '/app/detections',
    '/app/detections_json',
  ];

  final Map<String, Completer<Map<String, dynamic>>> _svcWaiters = {};

  bool get isConnected => _connected;

  Future<void> connect() async {
    if (_connected) return;
    try {
      onStatus('Connecting to $url ...');
      _ch = WebSocketChannel.connect(Uri.parse(url));
      _sub = _ch!.stream.listen(_onMessage, onError: (e) {
        onStatus('WS error: $e');
      }, onDone: () {
        _connected = false;
        onStatus('Disconnected');
      });

      await Future<void>.delayed(const Duration(milliseconds: 200));
      _connected = true;
      onStatus('Connected');

      _advertiseCompressedImage(publishTopic);
      _subscribe(annotatedTopic);
      for (final t in detectionTopics) {
        _subscribe(t);
      }
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
      for (final t in detectionTopics) {
        _unsubscribe(t);
      }
    } catch (_) {}
    _sub?.cancel();
    _ch?.sink.close();
    _sub = null;
    _ch = null;

    for (final c in _svcWaiters.values) {
      if (!c.isCompleted) c.completeError('Disconnected');
    }
    _svcWaiters.clear();
  }

  void publishJpeg(Uint8List jpegBytes) {
    if (!_connected || _ch == null) {
      onStatus('Not connected; drop frame');
      return;
    }
    final b64 = base64Encode(jpegBytes);
    _send({
      'op': 'publish',
      'topic': publishTopic,
      'msg': {'format': 'jpeg', 'data': b64},
    });
    onStatus('Frame sent: ${jpegBytes.length} bytes');
  }

  Future<(bool ok, int? roundTripMs)> ping({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (!_connected || _ch == null) return (false, null);
    final id = _uuid.v4();
    final c = Completer<Map<String, dynamic>>();
    _svcWaiters[id] = c;
    final t0 = DateTime.now().millisecondsSinceEpoch;
    _send({
      'op': 'call_service',
      'id': id,
      'service': '/rosapi/get_time',
      'args': {},
    });

    try {
      final resp = await c.future.timeout(timeout);
      final result = (resp['result'] == true);
      final t1 = DateTime.now().millisecondsSinceEpoch;
      return (result, t1 - t0);
    } catch (_) {
      return (false, null);
    } finally {
      _svcWaiters.remove(id);
    }
  }

  void _advertiseCompressedImage(String topic) {
    _send({
      'op': 'advertise',
      'id': _uuid.v4(),
      'topic': topic,
      'type': 'sensor_msgs/CompressedImage',
    });
  }

  void _unadvertise(String topic) =>
      _send({'op': 'unadvertise', 'id': _uuid.v4(), 'topic': topic});

  void _subscribe(String topic) =>
      _send({'op': 'subscribe', 'id': _uuid.v4(), 'topic': topic});

  void _unsubscribe(String topic) =>
      _send({'op': 'unsubscribe', 'id': _uuid.v4(), 'topic': topic});

  void _send(Map<String, dynamic> jsonMsg) {
    if (_ch == null) return;
    _ch!.sink.add(jsonEncode(jsonMsg));
  }

  void _onMessage(dynamic data) {
    try {
      final obj = jsonDecode(data as String) as Map<String, dynamic>;
      if (obj['op'] == 'service_response' && obj['id'] is String) {
        final id = obj['id'] as String;
        final w = _svcWaiters[id];
        if (w != null && !w.isCompleted) w.complete(obj);
        return;
      }

      if (obj['op'] == 'publish' && obj['topic'] is String) {
        final topic = obj['topic'] as String;
        final msg = obj['msg'];

        if (topic == annotatedTopic && msg is Map) {
          final b64 = msg['data'] as String?;
          if (b64 != null) {
            final bytes = base64Decode(b64);
            onAnnotatedImage(bytes);
            onStatus('Annotated image received (${bytes.length} bytes)');
          }
          return;
        }

        if (detectionTopics.contains(topic)) {
          if (msg is Map && msg.containsKey('data')) {
            final raw = msg['data']?.toString() ?? '{}';
            try {
              onDetections(jsonDecode(raw) as Map<String, dynamic>);
              onStatus('Detections JSON received ✓');
            } catch (_) {
              onDetections({'raw': raw, 'note': 'not a valid JSON'});
              onStatus('Detections received (raw string)');
            }
          } else if (msg is Map<String, dynamic>) {
            onDetections(msg);
            onStatus('Detections map received ✓');
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
