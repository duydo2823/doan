import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';           // PlatformException
import 'package:image_picker/image_picker.dart';
import 'result_page.dart';

class DetectIntroPage extends StatefulWidget {
  static const routeName = '/detect-intro';
  const DetectIntroPage({super.key});

  @override
  State<DetectIntroPage> createState() => _DetectIntroPageState();
}

class _DetectIntroPageState extends State<DetectIntroPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _captured;
  String? _errorMsg; // ví dụ: "Permission denied: camera"

  Future<void> _capture() async {
    setState(() => _errorMsg = null);

    try {
      final x = await _picker.pickImage(source: ImageSource.camera);
      if (x != null) {
        setState(() => _captured = x);
        // TODO: nếu cần gửi ảnh lên ROS, xử lý tại đây với File(x.path)
      }
      // Nếu người dùng bấm cancel thì _captured vẫn null, không báo lỗi.
    } on PlatformException catch (e) {
      // image_picker trả PlatformException khi quyền bị chặn/từ chối
      // Trên iOS có thể là 'camera_access_denied'
      if (e.code.contains('denied')) {
        setState(() => _errorMsg = 'Permission denied: camera');
      } else {
        setState(() => _errorMsg = 'Lỗi camera: ${e.code}');
      }
    } catch (e) {
      setState(() => _errorMsg = 'Không mở được camera: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _captured != null;

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
              if (_errorMsg != null) ...[
                Text(_errorMsg!, style: const TextStyle(color: Colors.black87)),
                const SizedBox(height: 8),
              ],

              // Nút chụp & gửi
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
                  onPressed: _capture,
                ),
              ),

              const SizedBox(height: 16),

              // Ảnh preview xuất hiện ngay dưới sau khi chụp
              if (hasImage)
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(_captured!.path),
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                )
              else
                const Expanded(child: SizedBox()),

              // Nút Xem kết quả ở đáy (sang Trang 3)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.visibility),
                    label: const Text('Xem kết quả'),
                    onPressed: hasImage
                        ? () => Navigator.pushNamed(
                      context,
                      ResultPage.routeName,
                      arguments: _captured!.path,
                    )
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
