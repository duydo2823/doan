import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Client đơn giản cho rosbridge_server.
/// Hỗ trợ:
///  - Kết nối / ngắt
///  - Ping thật sự qua rosapi (để biết rosbridge đã ready)
///  - Gửi ảnh JPEG lên topic /app/image/compressed
///  - Nhận ảnh annotated từ /app/annotated/compressed (và /video/annotated nếu có)
///  - Nhận JSON bbox từ /app/detections_json
class RosbridgeClient {
  final String url;

  final void Function(String status)? onStatus;

  /// Ảnh annotated (ROS đã vẽ bounding box) – dùng cho DetectIntroPage
  final void Function(Uint8List jpeg)? onAnnotatedImage;

  /// Detections JSON (bbox, cls, score, image size,…)
  final void Function(Map<String, dynamic> json)? onDetections;

  /// Nếu bạn dùng trong VideoStreamPage kiểu onAnnotatedFrame
  final void Function(Uint8List jpeg)? onAnnotatedFrame;

  WebSocketChannel? _socket;
  StreamSubscription? _sub;

  bool get isConnected => _socket != null;

  // --- ping via rosapi call ---
  int _callId = 0;
  final Map<String, Completer<Map<String, dynamic>>> _pendingCalls = {};

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
      _socket = WebSocketChannel.connect(Uri.parse(url));
      onStatus?.call('Connected');

      _sub = _socket!.stream.listen(
        _onMessage,
        onDone: () {
          onStatus?.call('Disconnected');
          _socket = null;
          _failAllPending('Socket closed');
        },
        onError: (e) {
          onStatus?.call('Error: $e');
          _socket = null;
          _failAllPending('Socket error: $e');
        },
      );

      _advertiseAndSubscribe();
    } catch (e) {
      onStatus?.call('Connection error: $e');
      _socket = null;
    }
  }

  void disconnect() {
    _sub?.cancel();
    _sub = null;
    _socket?.sink.close();
    _socket = null;
    _failAllPending('Manual disconnect');
    onStatus?.call('Disconnected');
  }

  void _failAllPending(String reason) {
    final keys = _pendingCalls.keys.toList();
    for (final k in keys) {
      _pendingCalls[k]?.completeError(reason);
      _pendingCalls.remove(k);
    }
  }

  // ================== ADVERTISE / SUBSCRIBE ==================

  void _sendRaw(Map<String, dynamic> msg) {
    if (_socket == null) return;
    _socket!.sink.add(jsonEncode(msg));
  }

  void _advertiseAndSubscribe() {
    // Advertise topic để gửi ảnh lên ROS
    _sendRaw({
      'op': 'advertise',
      'topic': '/app/image/compressed',
      'type': 'sensor_msgs/CompressedImage',
    });

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

    // (Tuỳ bạn có video node riêng)
    _sendRaw({
      'op': 'subscribe',
      'topic': '/video/annotated',
      'type': 'sensor_msgs/CompressedImage',
    });
  }

  // ================== PUBLISH JPEG LÊN ROS ==================

  /// Gửi 1 frame JPEG lên topic /app/image/compressed
  void publishJpeg(Uint8List bytes) {
    if (_socket == null) return;

    final msg = {
      'op': 'publish',
      'topic': '/app/image/compressed',
      'msg': {
        'format': 'jpeg',
        // rosbridge thường mong base64 khi publish
        'data': base64Encode(bytes),
      },
    };

    _socket!.sink.add(jsonEncode(msg));
  }

  // ================== ROSAPI CALL (PING THẬT) ==================

  Future<Map<String, dynamic>> _callService({
    required String service,
    Map<String, dynamic>? args,
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    if (_socket == null) {
      throw StateError('Socket not connected');
    }

    _callId++;
    final id = 'call_$_callId';
    final c = Completer<Map<String, dynamic>>();
    _pendingCalls[id] = c;

    _sendRaw({
      'op': 'call_service',
      'service': service,
      'args': args ?? {},
      'id': id,
    });

    return c.future.timeout(timeout, onTimeout: () {
      _pendingCalls.remove(id);
      throw TimeoutException('call_service timeout: $service');
    });
  }

  /// Ping thật sự:
  /// - gọi /rosapi/get_time để biết rosbridge đã ready + RTT tương đối
  Future<(bool, int?)> ping() async {
    if (!isConnected) return (false, null);

    final sw = Stopwatch()..start();
    try {
      await _callService(service: '/rosapi/get_time');
      sw.stop();
      return (true, sw.elapsedMilliseconds);
    } catch (_) {
      sw.stop();
      return (false, null);
    }
  }

  // ================== HANDLE MESSAGE TỪ ROS ==================

  Uint8List? _decodeCompressedData(dynamic payload) {
    // ROSBRIDGE có thể trả:
    // - base64 String
    // - List<int> (mảng byte)
    if (payload is String) {
      try {
        return base64Decode(payload);
      } catch (_) {
        return null;
      }
    }
    if (payload is List) {
      try {
        return Uint8List.fromList(payload.cast<int>());
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  void _onMessage(dynamic data) {
    try {
      final jsonData = jsonDecode(data);
      if (jsonData is! Map) return;

      // ====== handle service response (ping) ======
      if (jsonData['op'] == 'service_response' && jsonData['id'] != null) {
        final id = jsonData['id'].toString();
        final c = _pendingCalls.remove(id);
        if (c != null) {
          c.complete(Map<String, dynamic>.from(jsonData));
        }
        return;
      }

      if (jsonData['op'] != 'publish') return;

      final topic = jsonData['topic'];
      final msg = jsonData['msg'];

      // Ảnh annotated (đã vẽ bbox)
      if (topic == '/app/annotated/compressed' || topic == '/video/annotated') {
        final payload = msg['data'];
        final bytes = _decodeCompressedData(payload);
        if (bytes != null) {
          onAnnotatedImage?.call(bytes);
          onAnnotatedFrame?.call(bytes);
        } else {
          onStatus?.call(
              'Annotated received but unsupported data type: ${payload.runtimeType}');
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
