import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/rosbridge_client.dart';
import 'result_page.dart';

class DetectIntroPage extends StatefulWidget {
  static const routeName = '/detect-intro';
  const DetectIntroPage({super.key});

  @override
  State<DetectIntroPage> createState() => _DetectIntroPageState();
}

class _DetectIntroPageState extends State<DetectIntroPage> {
  final ImagePicker _picker = ImagePicker();

  // cấu hình rosbridge — đổi ip theo mạng của bạn
  static const _rosUrl = 'ws://192.168.1.100:9090';

  late final RosbridgeClient _ros;
  String _status = 'Disconnected';
  XFile? _captured;            // ảnh gốc vừa chụp
  Uint8List? _annotatedBytes;  // ảnh annotate từ ROS
  Map<String, dynamic>? _detections; // JSON kết quả

  @override
  void initState() {
    super.initState();
    _ros = RosbridgeClient(
      url: _rosUrl,
      onStatus: (s) => setState(() => _status = s),
      onAnnotatedImage: (jpeg) => setState(() => _annotatedBytes = jpeg),
      onDetections: (m) => setState(() => _detections = m),
    );
    _ros.connect();
  }

  @override
  void dispose() {
    _ros.disconnect();
    super.dispose();
  }

  Future<void> _captureAndSend() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.camera);
      if (x == null) return; // user cancel
      setState(() {
        _captured = x;
        _annotatedBytes = null; // reset annotate cũ
      });
      final bytes = await File(x.path).readAsBytes();
      _ros.publishJpeg(bytes);
    } on PlatformException catch (e) {
      // image_picker sẽ xin quyền, nếu bị từ chối sẽ throw
      final denied = e.code.contains('denied');
      setState(() => _status = denied ? 'Permission denied: camera' : 'Camera error: ${e.code}');
    } catch (e) {
      setState(() => _status = 'Không mở được camera: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _captured != null;
    final hasAnnotated = _annotatedBytes != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF43A047),
        foregroundColor: Colors.white,
        title: const Text('Phát hiện bệnh lá cà phê'),
      ),
      backgroundColor: const Color(0xFFF4F8F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_status, style: const TextStyle(color: Colors.black87)),
              const SizedBox(height: 8),

              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Chụp & gửi lên ROS'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF43A047),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: _ros.isConnected ? _captureAndSend : null,
                ),
              ),

              const SizedBox(height: 12),

              // Ảnh gốc / annotate — hiển thị ngay bên dưới
              Expanded(
                child: hasAnnotated
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _annotatedBytes!,
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                )
                    : (hasImage
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(_captured!.path),
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                )
                    : const SizedBox()),
              ),

              // Nút sang Trang 3 + pass kết quả/ảnh
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.visibility),
                    label: const Text('Xem kết quả'),
                    onPressed: hasImage
                        ? () {
                      Navigator.pushNamed(
                        context,
                        ResultPage.routeName,
                        arguments: {
                          'rawPath': _captured!.path,
                          'annotated': _annotatedBytes,
                          'detections': _detections,
                        },
                      );
                    }
                        : null,
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
