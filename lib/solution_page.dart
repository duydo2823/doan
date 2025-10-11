import 'dart:typed_data';
import 'package:flutter/material.dart';

/// ===== In-memory history cho phiên app =====
class DetectionRecord {
  final DateTime time;
  final List<String> diseases; // keys đã normalize
  final Uint8List? image;
  DetectionRecord({required this.time, required this.diseases, this.image});
}

class DetectionHistory {
  static final List<DetectionRecord> items = [];
  static void add(DetectionRecord r) => items.insert(0, r);
  static void clear() => items.clear();
}

/// ===== Trang kết quả + lịch sử =====
class SolutionPage extends StatefulWidget {
  const SolutionPage({super.key});

  @override
  State<SolutionPage> createState() => _SolutionPageState();
}

class _SolutionPageState extends State<SolutionPage> {
  // Bảng giải pháp cho các nhãn mô hình
  static const Map<String, String> _solutions = {
    'cercospora':
    '🍂 Cercospora (đốm lá):\n• Cắt bỏ lá bệnh, vệ sinh vườn.\n• Phun Chlorothalonil/Carbendazim luân phiên.\n• Hạn chế tưới lên tán lá, cải thiện thoát nước.',
    'miner':
    '🐛 Miner (sâu đục lá):\n• Dùng Bt/Abamectin theo hướng dẫn.\n• Tỉa cành, giảm rậm rạp.\n• Giám sát thường xuyên.',
    'phoma':
    '🟤 Phoma:\n• Phun thuốc gốc đồng.\n• Tăng cường phân bón kali, cân đối NPK.\n• Thu gom lá bệnh, giữ vườn sạch.',
    'rust':
    '🌾 Rust (gỉ sắt):\n• Cắt tỉa và tiêu huỷ lá bệnh.\n• Phun gốc đồng/Mancozeb theo khuyến cáo.\n• Thoáng tán, giảm ẩm độ.',
    'healthy':
    '🍃 Lá khoẻ:\n• Duy trì chăm sóc, tưới tiêu hợp lý.\n• Bón phân cân đối, phòng bệnh định kỳ.',
    'unknown': 'Chưa có thông tin cho loại bệnh này.',
  };

  // State lần hiện tại
  List<String> _keys = []; // danh sách bệnh đã normalize
  Uint8List? _image;

  bool _initialized = false; // tránh đọc args nhiều lần

  // Đọc arguments AN TOÀN sau khi context sẵn sàng
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final args =
    ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;

    final diseasesArg = (args?['diseases'] is List)
        ? List<String>.from(args!['diseases'])
        : <String>[];

    _keys = diseasesArg
        .map((e) => e.toLowerCase().replaceAll(' ', '_'))
        .toSet()
        .toList();

    _image = args?['image'] as Uint8List?;

    // ✅ Chỉ lưu vào lịch sử nếu có ảnh
    if (_image != null) {
      DetectionHistory.add(
        DetectionRecord(time: DateTime.now(), diseases: _keys, image: _image),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF2E7D32);

    // Lọc lịch sử chỉ những bản ghi có ảnh
    final historyWithImage =
    DetectionHistory.items.where((e) => e.image != null).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kết quả & lịch sử'),
        backgroundColor: primary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1) ẢNH LẦN CHỤP HIỆN TẠI
          if (_image != null) ...[
            _sectionTitle('Ảnh đã chụp/annotated'),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_image!, fit: BoxFit.contain),
            ),
            const SizedBox(height: 16),
          ],

          // 2) TẤT CẢ BỆNH ĐÃ NHẬN DIỆN TRONG LẦN NÀY
          _sectionTitle('Các bệnh đã nhận diện'),
          const SizedBox(height: 8),
          if (_keys.isEmpty)
            const Text('Không có bệnh nào được phát hiện.')
          else
            ..._keys.map(
                  (k) => _solutionCard(k, _solutions[k] ?? _solutions['unknown']!),
            ),

          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // 3) LỊCH SỬ (chỉ hiển thị mục có ảnh)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionTitle('Lịch sử các lần chụp'),
              TextButton.icon(
                onPressed: () {
                  setState(() => DetectionHistory.clear());
                },
                icon: const Icon(Icons.delete_forever),
                label: const Text('Xoá lịch sử'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (historyWithImage.isEmpty)
            const Text('Chưa có lịch sử.')
          else
            ...historyWithImage.map(_historyTile),
        ],
      ),
    );
  }

  // ===== Widgets phụ =====
  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
  );

  Widget _solutionCard(String key, String description) {
    String pretty(String k) {
      if (k == 'healthy') return 'Không bệnh';
      if (k == 'unknown') return 'Không xác định';
      return k
          .replaceAll('_', ' ')
          .split(' ')
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
    }

    return Card(
      color: const Color(0xFFE9F7EE),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pretty(key),
                style:
                const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(description, style: const TextStyle(height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _historyTile(DetectionRecord r) {
    String when(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} '
            '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                r.image!, // r.image luôn != null vì đã lọc
                width: 72,
                height: 72,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(when(r.time),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: -6,
                    children: r.diseases
                        .map(
                          (k) => Chip(
                        label: Text(k.replaceAll('_', ' ')),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
