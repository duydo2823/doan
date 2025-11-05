import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
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
  static const _rosUrl = 'ws://192.168.1.251:9090';

  late final RosbridgeClient _ros;
  String _status = 'Disconnected';
  bool _lastPingOk = false;
  int? _lastRttMs;
  Timer? _hb;

  XFile? _captured;
  Uint8List? _annotatedBytes;
  Map<String, dynamic>? _detections;
  bool _isStreamingVideo = false;

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
      final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1280);
      if (x == null) return;
      setState(() {
        _captured = x;
        _annotatedBytes = null;
        _detections = null;
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

  // 🖼️ Chọn ảnh từ thư viện
  Future<void> _pickFromGalleryAndSend() async {
    if (!_ros.isConnected || !_lastPingOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa kết nối ROS hoặc ROS không phản hồi.')),
      );
      return;
    }
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1280);
      if (x == null) return;
      setState(() {
        _captured = x;
        _annotatedBytes = null;
        _detections = null;
      });
      final bytes = await File(x.path).readAsBytes();
      _ros.publishJpeg(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi ảnh từ thư viện lên ROS')),
        );
      }
    } on PlatformException catch (e) {
      setState(() => _status = 'Không mở thư viện ảnh: ${e.code}');
    } catch (e) {
      setState(() => _status = 'Lỗi mở thư viện: $e');
    }
  }

  // 🎥 Chọn video & stream các frame lên ROS
  Future<void> _pickVideoAndStreamFrames() async {
    if (!_ros.isConnected || !_lastPingOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa kết nối ROS hoặc ROS không phản hồi.')),
      );
      return;
    }
    try {
      final xv = await _picker.pickVideo(source: ImageSource.gallery);
      if (xv == null) return;

      final file = File(xv.path);
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      final dur = controller.value.duration;
      await controller.dispose();

      setState(() {
        _captured = null;
        _annotatedBytes = null;
        _detections = null;
        _isStreamingVideo = true;
        _status = 'Đang gửi frame từ video...';
      });

      const frameIntervalMs = 400; // ~2.5 FPS
      const thumbQuality = 75;
      const maxH = 720;

      for (int t = 0; t <= dur.inMilliseconds; t += frameIntervalMs) {
        if (!_isStreamingVideo) break;
        final bytes = await VideoThumbnail.thumbnailData(
          video: xv.path,
          timeMs: t,
          imageFormat: ImageFormat.JPEG,
          quality: thumbQuality,
          maxHeight: maxH,
        );
        if (bytes == null) continue;
        _ros.publishJpeg(bytes);
        await Future.delayed(const Duration(milliseconds: 20));
      }

      if (mounted) {
        setState(() {
          _isStreamingVideo = false;
          _status = 'Đã gửi xong frame từ video';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi xong các frame từ video.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isStreamingVideo = false;
          _status = 'Lỗi xử lý video: $e';
        });
      }
    }
  }

  void _stopVideoStream() {
    setState(() => _isStreamingVideo = false);
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

              // ---- Kết nối / ngắt / kiểm tra ----
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

              // ---- Các nút chụp / chọn ảnh / chọn video ----
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Chụp ảnh'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canShoot ? const Color(0xFF43A047) : Colors.grey,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: canShoot ? _captureAndSend : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Chọn ảnh'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: const StadiumBorder(),
                        foregroundColor: const Color(0xFF2E7D32),
                      ),
                      onPressed: canShoot ? _pickFromGalleryAndSend : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.video_library_outlined),
                      label: Text(_isStreamingVideo ? 'Đang gửi video...' : 'Chọn video'),
                      onPressed: (!canShoot || _isStreamingVideo) ? null : _pickVideoAndStreamFrames,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: const StadiumBorder(),
                        foregroundColor: const Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Dừng gửi'),
                      onPressed: _isStreamingVideo ? _stopVideoStream : null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: const StadiumBorder(),
                        foregroundColor: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ---- Ảnh hiển thị ----
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (_captured == null && _annotatedBytes == null) {
                      return const Center(
                        child: Text(
                            'Chưa có ảnh hoặc video • Hãy kết nối ROS và chọn phương thức nhận diện'),
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
                                  : (_captured != null
                                  ? Image.file(File(_captured!.path))
                                  : const SizedBox()),
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

              // ---- Nút xem kết quả ----
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

// ---------------- Painter vẽ bbox ----------------
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
      const pad = 4.0;
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
