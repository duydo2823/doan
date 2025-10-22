import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class ResultPage extends StatelessWidget {
  static const routeName = '/result';
  const ResultPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final String? rawPath = args?['rawPath'] as String?;
    final Uint8List? annotated = args?['annotated'] as Uint8List?;
    final Map<String, dynamic>? detections =
    (args?['detections'] as Map?)?.cast<String, dynamic>();

    return Scaffold(
      appBar: AppBar(title: const Text('Kết quả nhận diện')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: annotated != null
                    ? Image.memory(annotated, fit: BoxFit.contain)
                    : (rawPath != null
                    ? Image.file(File(rawPath), fit: BoxFit.contain)
                    : const Center(child: Text('Không có ảnh'))),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Detections: ${detections ?? "N/A"}'),
            ),
            const SizedBox(height: 12),
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
