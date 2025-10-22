import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/history_storage.dart';
import 'history_page.dart';

class ResultPage extends StatelessWidget {
  static const routeName = '/result';
  const ResultPage({super.key});

  static const Map<String, Map<String, String>> kDiseaseGuide = {
    'Cercospora': {
      'vi': 'Đốm mắt cua (Cercospora)',
      'tip':
      '💡 Cắt bỏ lá nặng, dọn tán, giảm ẩm. Phun luân phiên thuốc gốc đồng hoặc triazole, bổ sung vi lượng Ca/Mg/Bo.'
    },
    'Miner': {
      'vi': 'Sâu đục lá (Leaf miner)',
      'tip':
      '💡 Ngắt lá bệnh nặng, đặt bẫy vàng dính. Phun Abamectin/Spinosad khi sâu non, hạn chế thuốc tràn lan.'
    },
    'Phoma': {
      'vi': 'Thán thư (Phoma)',
      'tip':
      '💡 Cắt lá bệnh, phun Mancozeb/Chlorothalonil/Difenoconazole. Giữ vườn thông thoáng, tránh ẩm.'
    },
    'Rust': {
      'vi': 'Rỉ sắt lá (Rust)',
      'tip':
      '💡 Thu gom lá bệnh, phun thuốc gốc đồng hoặc triazole. Bón phân cân đối, giảm đạm, tăng kali.'
    },
    'Healthy': {
      'vi': 'Lá khoẻ mạnh',
      'tip': '👍 Không phát hiện bệnh. Duy trì chăm sóc tốt, theo dõi định kỳ.'
    },
  };

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final String? rawPath = args?['rawPath'];
    final Uint8List? annotated = args?['annotated'];
    final Map<String, dynamic>? det = (args?['detections'] as Map?)?.cast<String, dynamic>();

    final List detections = (det?['detections'] is List) ? det!['detections'] as List : const [];
    final double? latency = (det?['latency_ms'] is num) ? (det!['latency_ms'] as num).toDouble() : null;

    // thời gian nhận diện
    final now = DateTime.now();
    final formatted = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);

    // bệnh có độ tin cậy cao nhất
    String topCls = 'Không rõ';
    double topScore = 0;
    if (detections.isNotEmpty) {
      final best = detections.reduce((a, b) => (a['score'] ?? 0) > (b['score'] ?? 0) ? a : b);
      topCls = best['cls'] ?? 'Unknown';
      topScore = (best['score'] ?? 0).toDouble();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kết quả nhận diện'),
        backgroundColor: const Color(0xFF43A047),
      ),
      backgroundColor: const Color(0xFFF5F8F5),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: annotated != null
                  ? Image.memory(annotated)
                  : (rawPath != null ? Image.file(File(rawPath)) : const SizedBox.shrink()),
            ),
            const SizedBox(height: 16),
            _infoCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🕒 Ngày giờ nhận diện: $formatted'),
                  if (latency != null)
                    Text('⏱ Thời gian xử lý: ${latency.toStringAsFixed(2)} ms'),
                  const SizedBox(height: 8),
                  const Text('Kết quả phát hiện:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  for (final d in detections)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        kDiseaseGuide[d['cls']]?['vi'] ?? d['cls'],
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                          'Độ tin cậy: ${(d['score'] ?? 0).toStringAsFixed(2)}\n${kDiseaseGuide[d['cls']]?['tip'] ?? ''}'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            FilledButton.icon(
              onPressed: () async {
                await DetectionHistoryStorage.addRecord({
                  'time': formatted,
                  'cls': topCls,
                  'score': topScore.toStringAsFixed(2),
                  'latency': latency?.toStringAsFixed(2) ?? '',
                  'path': rawPath ?? '',
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ Đã lưu kết quả vào lịch sử')),
                  );
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('Lưu kết quả'),
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
            ),

            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.history),
              label: const Text('Xem lịch sử nhận diện'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryPage()),
              ),
            ),

            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.popUntil(context, (route) => route.isFirst),
              icon: const Icon(Icons.home),
              label: const Text('Về trang đầu'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(Widget child) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: child,
    );
  }
}
