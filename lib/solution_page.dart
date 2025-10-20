import 'package:flutter/material.dart';

class SolutionPage extends StatelessWidget {
  SolutionPage({super.key});

  final Map<String, String> _solutions = const {
    'rust': '🌾 Bệnh gỉ sắt:\n• Cắt bỏ lá bệnh.\n• Phun thuốc gốc đồng / Mancozeb.\n• Tỉa tán, thông thoáng.',
    'leaf_spot': '🍂 Đốm lá:\n• Chlorothalonil/Carbendazim luân phiên.\n• Hạn chế tưới lên tán, thoát nước tốt.',
    'phoma': '🟤 Phoma:\n• Phun gốc đồng.\n• Tăng Kali, cân đối NPK.\n• Vệ sinh vườn, gom lá bệnh.',
    'miner': '🐛 Sâu đục lá:\n• Bt/Abamectin sinh học.\n• Tỉa cành.\n• Giám sát thường xuyên.',
    'healthy': '🍃 Lá khỏe:\n• Chăm sóc, tưới hợp lý.\n• Bón phân cân đối.\n• Theo dõi định kỳ.',
    'unknown': 'Chưa có thông tin cho loại bệnh này.',
  };

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final diseaseKey = (args?['disease'] ?? 'healthy').toString().toLowerCase();

    String prettyName(String k) {
      if (k == 'healthy') return 'Không bệnh';
      return k.replaceAll('_', ' ').split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');
    }

    final description = _solutions[diseaseKey] ?? _solutions['unknown']!;

    return Scaffold(
      appBar: AppBar(
        title: Text('Giải pháp: ${prettyName(diseaseKey)}'),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Card(
              color: const Color(0xFFE8F5E9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(description, style: const TextStyle(fontSize: 16, height: 1.4)),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Quay lại nhận diện'),
            ),
          ],
        ),
      ),
    );
  }
}
