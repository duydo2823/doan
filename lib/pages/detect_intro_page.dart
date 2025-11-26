// lib/pages/detect_intro_page.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../services/rosbridge_client.dart';
import 'result_page.dart';

// ====== Cấu hình mạng ======
const String ROS_IP = '172.16.0.237';
const int ROSBRIDGE_PORT = 9090;

// ====== Map tên bệnh tiếng Việt ======
const Map<String, String> kDiseaseVI = {
  'Cercospora': 'Đốm mắt cua (Cercospora)',
  'Miner': 'Sâu đục lá (Leaf miner)',
  'Phoma': 'Đốm lá/Thán thư (Phoma)',
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

  // ROS bridge
  late final RosbridgeClient _ros;
  String _status = 'Disconnected';
  bool _lastPingOk = false;
  int? _lastRttMs;
  Timer? _hb;

  // Camera
  List<CameraDescription> _cams = [];
  CameraController? _cam;
  bool _camOn = false;

  // Stream control
  bool _streamPaused = false;
  int _lastSendMs = 0;
  double _fpsSend = 3; // FPS gửi lên ROS (có slider chỉnh từ 1–10)

  // Dữ liệu từ ROS
  XFile? _captured;                  // ảnh tĩnh gần nhất (nếu có)
  Uint8List? _annotatedBytes;        // ảnh annotated từ ROS
  Map<String, dynamic>? _detections; // JSON detections từ ROS

  // =============== LIFECYCLE =================
  @override
  void initState() {
    super.initState();
    _ros = RosbridgeClient(
      url: 'ws://$ROS_IP:$ROSBRIDGE_PORT',
      onStatus: (s) => setState(() => _status = s),
      onAnnotatedImage: (jpeg) => setState(() => _annotatedBytes = jpeg),
      onDetections: (m) => setState(() => _detections = m),
    );
  }

  @override
  void dispose() {
    _stopHeartbeat();
    _ros.disconnect();
    _stopCamera();
    super.dispose();
  }

  // =============== ROS =================
  void _startHeartbeat() {
    _hb?.cancel();
    _hb = Timer.periodic(
      const Duration(seconds: 5),
          (_) => _doPing(silent: true),
    );
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
    _stopCamera();
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  // =============== CAMERA & STREAM =================
  Future<void> _initCamera() async {
    _cams = await availableCameras();
    final back = _cams.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cams.first,
    );
    _cam = CameraController(
      back,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await _cam!.initialize();
    setState(() {});
  }

  Future<void> _startCamera() async {
    if (_camOn) return;
    try {
      await _initCamera();
      _camOn = true;
      _streamPaused = false;
      _lastSendMs = 0;

      await _cam!.startImageStream((CameraImage imgRaw) async {
        if (!_camOn) return;
        if (_streamPaused) return;

        final now = DateTime.now().millisecondsSinceEpoch;
        final intervalMs = (1000 / _fpsSend).round().clamp(50, 1000);
        if (now - _lastSendMs < intervalMs) return;
        _lastSendMs = now;

        final jpeg = _convertYUVToJPEG(imgRaw);
        if (jpeg != null && _ros.isConnected && _lastPingOk) {
          _ros.publishJpeg(jpeg);
        }
      });

      setState(() {});
    } on CameraException catch (e) {
      setState(() {
        _status = 'Lỗi camera: ${e.code}';
      });
    } on PlatformException catch (e) {
      setState(() {
        _status = 'Lỗi quyền camera: ${e.code}';
      });
    }
  }

  Future<void> _stopCamera() async {
    _camOn = false;
    _streamPaused = false;
    try {
      if (_cam != null && _cam!.value.isStreamingImages) {
        await _cam!.stopImageStream();
      }
    } catch (_) {}
    setState(() {});
  }

  Uint8List? _convertYUVToJPEG(CameraImage image) {
    try {
      final width = image.width;
      final height = image.height;

      // Lấy plane Y (độ sáng) → chuyển sang ảnh grayscale
      final plane = image.planes[0];
      final int yRowStride = plane.bytesPerRow;

      // Tạo buffer đúng kích thước
      final bytes = Uint8List(width * height);

      int offset = 0;
      for (int y = 0; y < height; y++) {
        // copy mỗi dòng 1 lần → nhanh hơn rất nhiều
        bytes.setRange(
          offset,
          offset + width,
          plane.bytes,
          y * yRowStride,
        );
        offset += width;
      }

      // Chuyển thành ảnh grayscale (Format.luminance KHÔNG CÒN nữa)
      final img.Image gray = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: bytes.buffer,
        numChannels: 1, // grayscale
      );

      // Encode thành JPEG (nhẹ)
      return Uint8List.fromList(img.encodeJpg(gray, quality: 70));
    } catch (e) {
      print("Error converting YUV → JPEG: $e");
      return null;
    }
  }


  // =============== ẢNH TĨNH (CHỤP / CHỌN) =================
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
        _detections = null;
      });

      final bytes = await File(x.path).readAsBytes();
      _ros.publishJpeg(bytes);
    } catch (e) {
      setState(() => _status = 'Không chụp được ảnh: $e');
    }
  }

  Future<void> _pickFromGalleryAndSend() async {
    if (!_ros.isConnected || !_lastPingOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa kết nối ROS hoặc ROS không phản hồi.')),
      );
      return;
    }
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery);
      if (x == null) return;

      setState(() {
        _captured = x;
        _annotatedBytes = null;
        _detections = null;
      });

      final bytes = await File(x.path).readAsBytes();
      _ros.publishJpeg(bytes);
    } catch (e) {
      setState(() => _status = 'Không mở thư viện: $e');
    }
  }

  // =============== UI =================
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
                  color: connected && _lastPingOk
                      ? Colors.lightGreenAccent
                      : Colors.redAccent,
                ),
                const SizedBox(width: 6),
                Text(
                  connected ? (_lastPingOk ? 'Online' : 'No ping') : 'Offline',
                  style: const TextStyle(fontSize: 12),
                ),
                if (_lastRttMs != null) ...[
                  const SizedBox(width: 6),
                  Text('${_lastRttMs}ms',
                      style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF4F8F5),

      // ======= Nút Xem kết quả =======
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            icon: const Icon(Icons.visibility),
            label: const Text('Xem kết quả'),
            onPressed: () {
              if (_captured == null &&
                  _annotatedBytes == null &&
                  _detections == null) {
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
        ),
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_status, style: const TextStyle(color: Colors.black87)),
              const SizedBox(height: 8),

              // ======= 3 nút: Kết nối – Ngắt – Ping =======
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.power_settings_new),
                      label: Text(connected ? 'Đã kết nối' : 'Kết nối'),
                      onPressed: connected ? null : _connect,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.link_off),
                      label: const Text('Ngắt'),
                      onPressed: connected ? _disconnect : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.wifi_tethering),
                      label: const Text('Ping'),
                      onPressed: connected ? _doPing : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ======= Nút chụp / chọn ảnh (tĩnh) =======
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Chụp ảnh'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        canShoot ? const Color(0xFF43A047) : Colors.grey,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        shape: const StadiumBorder(),
                        foregroundColor: const Color(0xFF2E7D32),
                      ),
                      onPressed: canShoot ? _pickFromGalleryAndSend : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ======= Bật Camera + Pause + FPS =======
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: Icon(_camOn ? Icons.stop : Icons.videocam),
                      label: Text(_camOn ? 'Dừng Camera' : 'Bật Camera stream'),
                      onPressed: connected
                          ? (_camOn ? _stopCamera : _startCamera)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(
                          _streamPaused ? Icons.play_arrow : Icons.pause_outlined),
                      label:
                      Text(_streamPaused ? 'Tiếp tục gửi' : 'Tạm dừng gửi'),
                      onPressed: _camOn
                          ? () {
                        setState(() {
                          _streamPaused = !_streamPaused;
                        });
                      }
                          : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ======= Slider chỉnh FPS =======
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FPS gửi ROS: ${_fpsSend.toStringAsFixed(0)} fps',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Slider(
                    min: 1,
                    max: 10,
                    divisions: 9,
                    value: _fpsSend,
                    label: '${_fpsSend.toStringAsFixed(0)} fps',
                    onChanged: (v) {
                      setState(() => _fpsSend = v);
                    },
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ======= CAMERA PREVIEW + BOUNDING BOX OVERLAY =======
              AspectRatio(
                aspectRatio: _cam != null && _cam!.value.isInitialized
                    ? _cam!.value.aspectRatio
                    : 3 / 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final h = constraints.maxHeight;

                      final boxes =
                      (_detections != null && _detections!['detections'] is List)
                          ? List<Map<String, dynamic>>.from(
                          _detections!['detections'])
                          : const <Map<String, dynamic>>[];

                      final imgW =
                      (_detections?['image']?['width'] as num?)?.toDouble();
                      final imgH =
                      (_detections?['image']?['height'] as num?)?.toDouble();

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          // Preview camera
                          if (_cam != null && _cam!.value.isInitialized)
                            CameraPreview(_cam!)
                          else
                            Container(
                              color: Colors.grey.shade300,
                              child: const Center(child: Text('Camera tắt')),
                            ),

                          // Overlay bbox real-time (nếu có JSON + kích thước ảnh)
                          if (boxes.isNotEmpty && imgW != null && imgH != null)
                            CustomPaint(
                              painter: _BoxesPainter(
                                boxes: boxes,
                                imageW: imgW,
                                imageH: imgH,
                                label: (m) {
                                  final cls = (m['cls'] ?? '').toString();
                                  final vi = kDiseaseVI[cls] ?? cls;
                                  final score = (m['score'] is num)
                                      ? (m['score'] as num).toDouble()
                                      : 0.0;
                                  return '${vi.split('(').first.trim()} ${score.toStringAsFixed(2)}';
                                },
                              ),
                              size: Size(w, h),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ======= ẢNH KẾT QUẢ ANNOTATED (ô dưới) =======
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _annotatedBytes != null
                      ? Image.memory(_annotatedBytes!, fit: BoxFit.contain)
                      : const Center(
                    child: Text(
                      'Chưa có ảnh kết quả từ ROS.\nBật camera hoặc chụp/chọn ảnh để nhận diện.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============== Painter vẽ bounding box =================
class _BoxesPainter extends CustomPainter {
  _BoxesPainter({
    required this.boxes,
    required this.imageW,
    required this.imageH,
    required this.label,
  });

  final List<Map<String, dynamic>> boxes;
  final double imageW;
  final double imageH;
  final String Function(Map<String, dynamic>) label;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / imageW;
    final sy = size.height / imageH;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF00BCD4);

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xAA00BCD4);

    for (final m in boxes) {
      final bb = (m['bbox'] as List?)
          ?.map((e) => (e as num).toDouble())
          .toList();
      if (bb == null || bb.length < 4) continue;

      final x1 = bb[0] * sx;
      final y1 = bb[1] * sy;
      final x2 = bb[2] * sx;
      final y2 = bb[3] * sy;

      final rect = Rect.fromLTRB(x1, y1, x2, y2);
      canvas.drawRect(rect, stroke);

      final textSpan = TextSpan(
        text: label(m),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      tp.layout();

      const pad = 3.0;
      final labelRect = Rect.fromLTWH(
        rect.left,
        rect.top - tp.height - pad * 2,
        tp.width + pad * 2,
        tp.height + pad * 2,
      );
      canvas.drawRect(labelRect, fill);
      tp.paint(canvas, Offset(labelRect.left + pad, labelRect.top + pad));
    }
  }

  @override
  bool shouldRepaint(covariant _BoxesPainter old) {
    return old.boxes != boxes ||
        old.imageW != imageW ||
        old.imageH != imageH;
  }
}
