import 'package:flutter/material.dart';
import 'camera_page.dart';

class DetectIntroPage extends StatelessWidget {
  static const routeName = '/detect-intro';
  const DetectIntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trang 2: Giới thiệu nhận diện')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Hệ thống sẽ mở camera để chụp ảnh đầu vào. Ảnh chụp xong có nút Xem kết quả để chuyển sang Trang 3.',
              style: TextStyle(fontSize: 16),
            ),
            const Spacer(),
            FilledButton.icon(
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Bắt đầu chụp'),
              onPressed: () =>
                  Navigator.pushNamed(context, CameraPage.routeName),
            ),
          ],
        ),
      ),
    );
  }
}
