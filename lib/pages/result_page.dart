import 'dart:io';
import 'package:flutter/material.dart';

class ResultPage extends StatelessWidget {
  static const routeName = '/result';
  const ResultPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String? imagePath =
    ModalRoute.of(context)?.settings.arguments as String?;

    return Scaffold(
      appBar: AppBar(title: const Text('Trang 3: Kết quả')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (imagePath != null) ...[
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Kết quả nhận diện (demo): Chưa xử lý mô hình.\nTại đây bạn tích hợp YOLO/TF Lite/ONNX...',
                textAlign: TextAlign.center,
              ),
            ] else ...[
              const Expanded(
                child: Center(child: Text('Không có ảnh đầu vào.')),
              )
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.home),
              label: const Text('Về trang đầu'),
              onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            ),
          ],
        ),
      ),
    );
  }
}
