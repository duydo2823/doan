import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../services/history_storage.dart';
import 'history_page.dart';

/// Map tên bệnh EN -> VI (hiển thị)
const Map<String, String> kDiseaseVI = {
  'Cercospora': 'Đốm mắt cua (Cercospora)',
  'Miner'     : 'Sâu đục lá (Leaf miner)',
  'Phoma'     : 'Thán thư (Phoma)',
  'Rust'      : 'Rỉ sắt lá (Rust)',
  'Healthy'   : 'Lá khoẻ mạnh',
};

/// Hướng dẫn xử lý/phòng ngừa (rút gọn, thực tế bạn có thể mở rộng thêm)
const Map<String, Map<String, String>> kDiseaseGuide = {
  'Cercospora': {
    'vi' : 'Đốm mắt cua (Cercospora)',
    'mo' : 'Vết đốm tròn nâu đậm viền đỏ, trung tâm xám nhạt; thường ở lá già.',
    'tip': 'Tỉa thông thoáng; thu gom lá bệnh; phun đồng hoặc Mancozeb luân phiên; bón cân đối N-P-K + vi lượng.',
  },
  'Miner': {
    'vi' : 'Sâu đục lá (Leaf miner)',
    'mo' : 'Đường ngoằn ngoèo nâu vàng trong phiến lá, lá thủng/khô mép.',
    'tip': 'Ngắt lá nặng; đặt bẫy vàng; phun Abamectin/Spinosad lúc sâu non buổi chiều; bảo tồn thiên địch.',
  },
  'Phoma': {
    'vi' : 'Thán thư (Phoma)',
    'mo' : 'Đốm nâu cháy, lan nhanh theo hình oval, rìa xám trắng.',
    'tip': 'Cắt tỉa phần bệnh; vệ sinh vườn; phun Copper/Fosetyl-Al/Propineb xoay tua; tránh tưới ướt tán ban đêm.',
  },
  'Rust': {
    'vi' : 'Rỉ sắt lá (Rust)',
    'mo' : 'Ổ phấn vàng cam mặt dưới lá; lá úa rụng sớm.',
    'tip': 'Chọn giống kháng; cân đối dinh dưỡng; phun Triazole/Strobilurin khi chớm bệnh; tăng cường K, Mg.',
  },
  'Healthy': {
    'vi' : 'Lá khoẻ mạnh',
    'mo' : 'Không phát hiện bất thường đáng kể.',
    'tip': 'Duy trì chăm sóc, tưới tiêu hợp lý, bón cân đối và theo dõi định kỳ.',
  },
};

class ResultPage extends StatelessWidget {
  static const routeName = '/result';
  const ResultPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = (ModalRoute.of(context)?.settings.arguments ?? {}) as Map;
    final String? rawPath              = args['rawPath'] as String?;
    final Uint8List? annotated         = args['annotated'] as Uint8List?;
    final Map<String, dynamic>? detMap = args['detections'] as Map<String, dynamic>?;

    // Tính thông tin tổng quát
    final latencyStr = (detMap?['latency_ms'] is num)
        ? (detMap!['latency_ms'] as num).toStringAsFixed(2)
        : '-';

    // Gom detection theo bệnh, chỉ giữ score cao nhất
    final Map<String, double> bestByClass = _bestScoreByClass(detMap);
    // Lấy overall-best để lưu lịch sử
    final (String, double)? overallBest = _pickBestOverall(bestByClass);

    // Thời gian hiện tại để lưu lịch sử
    final now = DateTime.now();
    final timeStr =
        '${_dd(now.day)}/${_dd(now.month)}/${now.year} '
        '${_dd(now.hour)}:${_dd(now.minute)}:${_dd(now.second)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kết quả nhận diện'),
        backgroundColor: const Color(0xFF43A047),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Lịch sử',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryPage()),
            ),
          ),
        ],
      ),

      // Nút Lưu vào lịch sử
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.save_alt),
        label: const Text('Lưu kết quả'),
        onPressed: () async {
          final record = <String, dynamic>{
            // HistoryPage của bạn đang dùng các field này
            'path'   : rawPath,                                         // thumbnail
            'cls'    : overallBest != null
                ? (kDiseaseVI[overallBest.$1] ?? overallBest.$1)
                : '—',
            'score'  : overallBest != null
                ? overallBest.$2.toStringAsFixed(2)
                : '0.00',
            'time'   : timeStr,
            'latency': latencyStr,
          };
          await DetectionHistoryStorage.addRecord(record);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ Đã lưu vào lịch sử')),
            );
          }
        },
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Ảnh hiển thị
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 3 / 4, // giữ ảnh cân đối trên mobile
              child: Container(
                color: const Color(0xFFF3F5F7),
                child: annotated != null
                    ? Image.memory(annotated, fit: BoxFit.contain)
                    : (rawPath != null
                    ? Image.file(File(rawPath), fit: BoxFit.contain)
                    : const Center(child: Text('Chưa có ảnh'))),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Thông tin thời gian & latency
          _infoTile(
            icon: Icons.schedule,
            title: 'Ngày giờ nhận diện',
            value: timeStr,
          ),
          _infoTile(
            icon: Icons.speed,
            title: 'Thời gian xử lý',
            value: '$latencyStr ms',
          ),
          const SizedBox(height: 8),

          // Kết quả theo bệnh (đã gộp)
          const Text('Kết quả phát hiện:', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),

          if (bestByClass.isEmpty)
            const Text('Không có phát hiện nào.'),
          ...bestByClass.entries.map((e) {
            final en = e.key;
            final score = e.value;
            final vi = kDiseaseVI[en] ?? en;
            final g  = kDiseaseGuide[en];
            return _diseaseCard(
              title: '$vi',
              conf : score,
              desc : g?['mo'] ?? '',
              tip  : g?['tip'] ?? '',
            );
          }).toList(),
          const SizedBox(height: 80), // chừa khoảng cho FAB
        ],
      ),
    );
  }

  // ---- Helpers --------------------------------------------------------------

  static Map<String, double> _bestScoreByClass(Map<String, dynamic>? det) {
    final list = (det?['detections'] as List?) ?? const [];
    final Map<String, double> best = {};
    for (final m in list) {
      final cls = (m['cls'] ?? '').toString();
      final sc  = (m['score'] is num) ? (m['score'] as num).toDouble() : 0.0;
      if (!best.containsKey(cls) || sc > best[cls]!) {
        best[cls] = sc;
      }
    }
    return best;
  }

  static (String, double)? _pickBestOverall(Map<String, double> bestByClass) {
    String? k;
    double  v = -1;
    bestByClass.forEach((cls, sc) {
      if (sc > v) { v = sc; k = cls; }
    });
    return k == null ? null : (k!, v);
  }

  static Widget _infoTile({required IconData icon, required String title, required String value}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2E7D32)),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(value),
        ],
      ),
    );
  }

  static Widget _diseaseCard({
    required String title,
    required double conf,
    required String desc,
    required String tip,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Độ tin cậy: ${conf.toStringAsFixed(2)}'),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(desc),
          ],
          if (tip.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💡 '),
                Expanded(child: Text(tip)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _dd(int n) => n.toString().padLeft(2, '0');
}
