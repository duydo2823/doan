import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Client đơn giản cho rosbridge_server.
///
/// Hỗ trợ:
///  - Kết nối / ngắt
///  - Ping (trả về (bool, int?) để dùng với Stopwatch)
///  - Gửi ảnh JPEG lên topic /app/image/compressed
///  - Nhận ảnh annotated từ /app/annotated/compressed
///  - Nhận JSON bbox từ /app/detections_json
class RosbridgeClient {
  final String url;

  final void Function(String status)? onStatus;

  /// Ảnh annotated (ROS đã vẽ bounding box) – dùng cho DetectIntroPage
  final void Function(Uint8List jpeg)? onAnnotatedImage;

  /// Detections JSON (bbox, cls, score, image size,…)
  final void Function(Map<String, dynamic> json)? onDetections;

  /// Nếu bạn có dùng trong VideoStreamPage kiểu onAnnotatedFrame
  /// thì callback này sẽ được gọi y hệt onAnnotatedImage.
  final void Function(Uint8List jpeg)? onAnnotatedFrame;

  WebSocketChannel? _socket;
  StreamSubscription? _sub;

  bool get isConnected => _socket != null;

  // READY gate để tránh drop frame đầu
  Completer<void>? _readyCompleter;
  bool _advertised = false;
  bool _subscribed = false;

  RosbridgeClient({
    required this.url,
    this.onStatus,
    this.onAnnotatedImage,
    this.onDetections,
    this.onAnnotatedFrame,
  });

  // ================== CONNECT / DISCONNECT ==================

  Future<void> connect() async {
    try {
      onStatus?.call('Connecting to $url ...');

      _readyCompleter = Completer<void>();
      _advertised = false;
      _subscribed = false;

      _socket = WebSocketChannel.connect(Uri.parse(url));
      onStatus?.call('Connected');

      _sub = _socket!.stream.listen(
        _onMessage,
        onDone: () {
          onStatus?.call('Disconnected');
          _socket = null;
        },
        onError: (e) {
          onStatus?.call('Error: $e');
          _socket = null;
        },
      );

      _advertiseAndSubscribe();

      // ✅ Quan trọng: cho rosbridge/ROS một nhịp để “kịp subscribe”
      await Future.delayed(const Duration(milliseconds: 250));

      if (!(_readyCompleter?.isCompleted ?? true)) {
        _readyCompleter!.complete();
      }
    } catch (e) {
      onStatus?.call('Connection error: $e');
      _socket = null;
      if (!(_readyCompleter?.isCompleted ?? true)) {
        _readyCompleter!.completeError(e);
      }
    }
  }

  void disconnect() {
    _sub?.cancel();
    _sub = null;
    _socket?.sink.close();
    _socket = null;

    _advertised = false;
    _subscribed = false;

    onStatus?.call('Disconnected');
  }

  // ================== READY ==================

  Future<void> waitReady({Duration timeout = const Duration(seconds: 2)}) async {
    final c = _readyCompleter;
    if (c == null) return;
    try {
      await c.future.timeout(timeout);
    } catch (_) {
      // timeout thì vẫn cho publish tiếp (đỡ treo app),
      // nhưng sẽ re-advertise trước khi gửi.
    }
  }

  // ================== ADVERTISE / SUBSCRIBE ==================

  void _sendRaw(Map<String, dynamic> msg) {
    if (_socket == null) return;
    _socket!.sink.add(jsonEncode(msg));
  }

  void _advertiseAndSubscribe() {
    if (_socket == null) return;

    // Advertise topic để gửi ảnh lên ROS
    _sendRaw({
      'op': 'advertise',
      'topic': '/app/image/compressed',
      'type': 'sensor_msgs/CompressedImage',
    });
    _advertised = true;

    // Subscribe ảnh annotated (ROS trả về)
    _sendRaw({
      'op': 'subscribe',
      'topic': '/app/annotated/compressed',
      'type': 'sensor_msgs/CompressedImage',
    });

    // Subscribe detections JSON
    _sendRaw({
      'op': 'subscribe',
      'topic': '/app/detections_json',
      'type': 'std_msgs/String',
    });

    // Nếu node video riêng publish /video/annotated
    _sendRaw({
      'op': 'subscribe',
      'topic': '/video/annotated',
      'type': 'sensor_msgs/CompressedImage',
    });

    _subscribed = true;
  }

  // ================== PUBLISH JPEG LÊN ROS ==================

  /// Gửi 1 frame JPEG lên topic /app/image/compressed
  /// ✅ Đã sửa: đợi READY để tránh mất frame đầu
  Future<void> publishJpeg(Uint8List bytes) async {
    if (_socket == null) return;

    await waitReady();

    // Nếu reconnect hoặc advertise/subscribe chưa xong -> làm lại
    if (!_advertised || !_subscribed) {
      _advertiseAndSubscribe();
      await Future.delayed(const Duration(milliseconds: 150));
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

  // ================== PING ==================

  /// Ping đơn giản: chỉ kiểm tra còn kết nối không.
  /// Trả về (ok, null). RTT thực tế dùng Stopwatch ở ngoài.
  Future<(bool, int?)> ping() async {
    if (!isConnected) return (false, null);
    return (true, null);
  }

  // ================== HANDLE MESSAGE TỪ ROS ==================

  void _onMessage(dynamic data) {
    try {
      final jsonData = jsonDecode(data);
      if (jsonData is! Map) return;

      if (jsonData['op'] != 'publish') return;

      final topic = jsonData['topic'];
      final msg = jsonData['msg'];

      // Ảnh annotated (đã vẽ bbox)
      if (topic == '/app/annotated/compressed' ||
          topic == '/video/annotated') {
        final String? b64 = msg['data'];
        if (b64 != null) {
          final bytes = base64Decode(b64);
          onAnnotatedImage?.call(bytes);
          onAnnotatedFrame?.call(bytes);
        }
        return;
      }

      // Detections JSON
      if (topic == '/app/detections_json') {
        final String? s = msg['data'];
        if (s != null) {
          final decoded = jsonDecode(s);
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
