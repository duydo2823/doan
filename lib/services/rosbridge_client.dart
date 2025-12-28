import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

class RosbridgeClient {
  final String url;

  final void Function(String status)? onStatus;

  /// annotated jpeg + frameId (header.frame_id)
  final void Function(Uint8List jpeg, String? frameId)? onAnnotatedImage;

  /// detections json + requestId (json['request_id'])
  final void Function(Map<String, dynamic> json, String? requestId)? onDetections;

  /// optional for video page
  final void Function(Uint8List jpeg, String? frameId)? onAnnotatedFrame;

  WebSocketChannel? _socket;
  StreamSubscription? _sub;

  bool get isConnected => _socket != null;

  int _callId = 0;
  final Map<String, Completer<Map<String, dynamic>>> _pendingCalls = {};

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

  /// Publish JPEG kèm header.frame_id để match request
  void publishJpeg(
      Uint8List bytes, {
        required String frameId,
      }) {
    if (_socket == null) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final secs = nowMs ~/ 1000;
    final nsecs = (nowMs % 1000) * 1000000;

    final msg = {
      'op': 'publish',
      'topic': '/app/image/compressed',
      'msg': {
        'header': {
          'stamp': {'secs': secs, 'nsecs': nsecs},
          'frame_id': frameId,
        },
        'format': 'jpeg',
        'data': base64Encode(bytes),
      },
    };

    _socket!.sink.add(jsonEncode(msg));
  }

  Future<Map<String, dynamic>> _callService({
    required String service,
    Map<String, dynamic>? args,
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    if (_socket == null) throw StateError('Socket not connected');

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

    return c.future.timeout(timeout);
  }

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

  Uint8List? _decodeCompressedData(dynamic payload) {
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

      if (jsonData['op'] == 'service_response' && jsonData['id'] != null) {
        final id = jsonData['id'].toString();
        final c = _pendingCalls.remove(id);
        if (c != null) c.complete(Map<String, dynamic>.from(jsonData));
        return;
      }

      if (jsonData['op'] != 'publish') return;

      final topic = jsonData['topic'];
      final msg = jsonData['msg'];
      if (msg is! Map) return;

      // annotated image
      if (topic == '/app/annotated/compressed' || topic == '/video/annotated') {
        String? frameId;
        final header = msg['header'];
        if (header is Map && header['frame_id'] != null) {
          frameId = header['frame_id'].toString();
        }

        final bytes = _decodeCompressedData(msg['data']);
        if (bytes != null) {
          onAnnotatedImage?.call(bytes, frameId);
          onAnnotatedFrame?.call(bytes, frameId);
        }
        return;
      }

      // detections json
      if (topic == '/app/detections_json') {
        final String? s = msg['data'];
        if (s == null) return;

        final decoded = jsonDecode(s);
        Map<String, dynamic>? map;
        if (decoded is Map<String, dynamic>) {
          map = decoded;
        } else if (decoded is Map) {
          map = Map<String, dynamic>.from(decoded as Map);
        }
        if (map == null) return;

        final reqId = map['request_id']?.toString();
        onDetections?.call(map, reqId);
        return;
      }
    } catch (e) {
      onStatus?.call('Parse error: $e');
    }
  }
}
