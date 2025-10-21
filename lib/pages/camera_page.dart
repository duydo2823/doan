import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'result_page.dart';

class CameraPage extends StatefulWidget {
  static const routeName = '/camera';
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _captured;

  Future<void> _openCamera() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        setState(() => _captured = photo);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không mở được camera: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trang 2.5: Chụp ảnh')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(
                child: _captured == null
                    ? const Text('Chưa có ảnh. Nhấn "Chụp" để mở camera.')
                    : ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(_captured!.path),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.camera),
                    label: const Text('Chụp'),
                    onPressed: _openCamera,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.visibility),
                    label: const Text('Xem kết quả'),
                    onPressed: _captured == null
                        ? null
                        : () {
                      Navigator.pushNamed(
                        context,
                        ResultPage.routeName,
                        arguments: _captured!.path,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
