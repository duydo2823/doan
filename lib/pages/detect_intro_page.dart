import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/rosbridge_client.dart';
import 'result_page.dart';

// 🌿 Map tên bệnh tiếng Việt
const Map<String, String> kDiseaseVI = {
  'Cercospora': 'Đốm mắt cua (Cercospora)',
  'Miner': 'Sâu đục lá (Leaf miner)',
  'Phoma': 'Thán thư (Phoma)',
  'Rust': 'Rỉ sắt lá (Rust)',
  'Healthy': 'Lá khoẻ mạnh',
};

class DetectIntroPage extends StatefulWidget {
  static const routeName = '/detect-intro';
  const DetectIntroPage({super.key});

  @override
  State<DetectIntroPage> createState() => _DetectIntroPageState();
}

class _DetectIntroPageState extends State<DetectIntroPage> {
  final ImagePicker _picker = ImagePicker();

  // ⚠️ Đổi IP rosbridge theo máy ROS của bạn
  static const _rosUrl = 'ws://172.20.10.3:9090';

  late final RosbridgeClient _ros;
  String _status = 'Disconnected';
  bool _lastPingOk = false;
  int? _lastRttMs;
  Timer? _hb;

  XFile? _captured;
  Uint8List? _annotatedBytes;
  Map<String, dynamic>? _detections;

  @override
  void initState() {
    super.initState();
    _ros = RosbridgeClient(
      url: _rosUrl,
      onStatus: (s) => setState(() => _status = s),
      onAnnotatedImage: (jpeg) => setState(() => _annotatedBytes = jpeg),
      onDetections: (m) => setState(() => _detections = m),
    );
  }

  @override
  void dispose() {
    _stopHeartbeat();
    _ros.disconnect();
    super.dispose();
  }

  void _startHeartbeat() {
    _hb?.cancel();
    _hb = Timer.periodic(const Duration(seconds: 5), (_) => _doPing(silent: true));
  }

  void _stopHeartbeat() {
    _hb?.cancel();
    _hb = null;
  }

  Future<void> _connect() async {
    try {
      await _ros.connect();
      _startHeartbeat();
      await _doPing();
    } catch (_) {}
  }

  void _disconnect() {
    _stopHeartbeat();
    _ros.disconnect();
    setState(() {
      _lastPingOk = false;
      _lastRttMs = null;
    });
  }

  Future<void> _doPing({bool silent = false}) async {
    final (ok, rtt) = await _ros.ping();
    setState(() {
      _lastPingOk = ok;
      _lastRttMs = rtt;
    });
    if (!silent) {
      final msg = ok ? 'ROS OK • RTT ${rtt}ms' : 'Không thể ping ROS';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _captureAndSend() async {
    if (!_ros.isConnected || !_lastPingOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa kết nối ROS hoặc ROS không phản hồi.')),
      );
      return;
    }
    try {
      final x = await _picker.pickImage(source: ImageSource.camera);
      if (x == null) return;
      setState(() {
        _captured = x;
        _annotatedBytes = null;
      });
      final bytes = await File(x.path).readAsBytes();
      _ros.publishJpeg(bytes);
    } on PlatformException catch (e) {
      final denied = e.code.contains('denied');
      setState(() => _status = denied ? 'Permission denied: camera' : 'Camera error: ${e.code}');
    } catch (e) {
      setState(() => _status = 'Không mở được camera: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _ros.isConnected;
    final canShoot = connected && _lastPingOk;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF43A047),
        foregroundColor: Colors.white,
        title: const Text('Phát hiện bệnh lá cà phê'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 12,
                  color: connected && _lastPingOk ? Colors.lightGreenAccent : Colors.redAccent,
                ),
                const SizedBox(width: 6),
                Text(
                  connected ? (_lastPingOk ? 'Online' : 'No ping') : 'Offline',
                  style: const TextStyle(fontSize: 12),
                ),
                if (_lastRttMs != null) ...[
                  const SizedBox(width: 6),
                  Text('${_lastRttMs}ms', style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF4F8F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_status, style: const TextStyle(color: Colors.black87)),
              const SizedBox(height: 8),

              // ---- Kết nối / Ngắt / Kiểm tra ----
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.power_settings_new),
                    label: Text(connected ? 'Đã kết nối' : 'Kết nối'),
                    onPressed: connected ? null : _connect,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.link_off),
                    label: const Text('Ngắt'),
                    onPressed: connected ? _disconnect : null,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Kiểm tra kết nối'),
                    onPressed: connected ? _doPing : null,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ---- Chụp & gửi lên ROS ----
              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: const Text('Chụp & gửi lên ROS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: canShoot ? const Color(0xFF43A047) : Colors.grey,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: const StadiumBorder(),
                ),
                onPressed: canShoot ? _captureAndSend : null,
              ),

              const SizedBox(height: 12),

              // ---- Ảnh hiển thị + Bbox overlay ----
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (_captured == null && _annotatedBytes == null) {
                      return const Center(
                        child: Text('Chưa có ảnh • Kết nối ROS và bấm “Chụp & gửi lên ROS”'),
                      );
                    }

                    final boxes = (_detections != null && _detections!['detections'] is List)
                        ? List<Map<String, dynamic>>.from(_detections!['detections'])
                        : const <Map<String, dynamic>>[];

                    final imgW = (_detections?['image']?['width'] as num?)?.toDouble();
                    final imgH = (_detections?['image']?['height'] as num?)?.toDouble();

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: imgW ?? constraints.maxWidth,
                              height: imgH ?? constraints.maxHeight,
                              child: _annotatedBytes != null
                                  ? Image.memory(_annotatedBytes!)
                                  : Image.file(File(_captured!.path)),
                            ),
                          ),
                          if (_annotatedBytes == null && imgW != null && imgH != null && boxes.isNotEmpty)
                            CustomPaint(
                              painter: _BoxesPainter(
                                boxes: boxes,
                                imageW: imgW,
                                imageH: imgH,
                                label: (m) {
                                  final cls = (m['cls'] ?? '').toString();
                                  final vi = kDiseaseVI[cls] ?? cls;
                                  final score =
                                  (m['score'] is num) ? (m['score'] as num).toDouble() : 0.0;
                                  return '${vi.split('(').first.trim()} ${score.toStringAsFixed(2)}';
                                },
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),

              // ---- Kết quả phát hiện ----
              if (_detections != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Kết quả phát hiện:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      ...List<Map<String, dynamic>>.from(_detections!['detections'] ?? []).map((m) {
                        final cls = (m['cls'] ?? '').toString();
                        final vi = kDiseaseVI[cls] ?? cls;
                        final score =
                        (m['score'] is num) ? (m['score'] as num).toDouble() : 0.0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.local_florist,
                                  size: 18, color: Color(0xFF43A047)),
                              const SizedBox(width: 8),
                              Expanded(child: Text(vi)),
                              Text('${score.toStringAsFixed(2)}'),
                            ],
                          ),
                        );
                      }),
                      if (_detections?['latency_ms'] != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '⏱ Xử lý: ${(_detections!['latency_ms'] as num).toStringAsFixed(2)} ms',
                          style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 8),

              // ---- Nút Xem kết quả ----
              FilledButton.icon(
                icon: const Icon(Icons.visibility),
                label: const Text('Xem kết quả'),
                onPressed: () {
                  if (_captured == null && _annotatedBytes == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Chưa có dữ liệu để hiển thị')),
                    );
                    return;
                  }
                  Navigator.pushNamed(
                    context,
                    ResultPage.routeName,
                    arguments: {
                      'rawPath': _captured?.path,
                      'annotated': _annotatedBytes,
                      'detections': _detections,
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Painter vẽ khung bbox ----------------
class _BoxesPainter extends CustomPainter {
  _BoxesPainter({
    required this.boxes,
    required this.imageW,
    required this.imageH,
    required this.label,
  });

  final List<Map<String, dynamic>> boxes;
  final double imageW, imageH;
  final String Function(Map<String, dynamic>) label;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF00BCD4);

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xAA00BCD4);

    for (final m in boxes) {
      final bb = (m['bbox'] as List?)?.map((e) => (e as num).toDouble()).toList();
      if (bb == null || bb.length < 4) continue;
      final rect = Rect.fromLTRB(bb[0], bb[1], bb[2], bb[3]);

      canvas.drawRect(rect, stroke);

      final textSpan = TextSpan(
        text: label(m),
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      tp.layout();
      final pad = 4.0;
      final labelRect = Rect.fromLTWH(
          rect.left, rect.top - (tp.height + pad * 2), tp.width + pad * 2, tp.height + pad * 2);
      canvas.drawRect(labelRect, fill);
      tp.paint(canvas, Offset(labelRect.left + pad, labelRect.top + pad));
    }
  }

  @override
  bool shouldRepaint(covariant _BoxesPainter old) =>
      old.boxes != boxes || old.imageW != imageW || old.imageH != imageH;
}
