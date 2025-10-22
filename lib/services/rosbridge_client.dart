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

  // topics giống app Java
  final String publishTopic = '/app/image/compressed';
  final String annotatedTopic = '/app/annotated/compressed';
  final String detectionsTopic = '/app/detections';

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

      // Chờ 1 nhịp rồi advertise + subscribe
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
  }

  bool get isConnected => _connected;

  /// Gửi JPEG theo sensor_msgs/CompressedImage (format=jpeg, data=base64)
  void publishJpeg(Uint8List jpegBytes) {
    if (!_connected || _ch == null) {
      onStatus('Not connected; drop frame');
      return;
    }
    final b64 = base64Encode(jpegBytes); // NO_WRAP tương đương
    final payload = {
      'op': 'publish',
      'topic': publishTopic,
      'msg': {'format': 'jpeg', 'data': b64},
    };
    _send(payload);
    onStatus('Frame sent: ${jpegBytes.length} bytes');
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
      // rosbridge publish message có dạng: { op: 'publish', topic: '...', msg: {...} }
      if (obj['op'] == 'publish' && obj.containsKey('topic')) {
        final topic = obj['topic'] as String;
        final msg = obj['msg'];

        if (topic == annotatedTopic && msg is Map) {
          // sensor_msgs/CompressedImage
          final dataB64 = msg['data'] as String?;
          if (dataB64 != null) {
            final bytes = base64Decode(dataB64);
            onAnnotatedImage(bytes);
          }
        } else if (topic == detectionsTopic) {
          // JSON kết quả (std_msgs/String hoặc custom) -> cố gắng parse
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
