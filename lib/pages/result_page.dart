// lib/pages/result_page.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../services/history_storage.dart';
import 'history_page.dart';

/// Map tên bệnh EN -> VI (tiêu đề hiển thị)
const Map<String, String> kDiseaseVI = {
  'Cercospora': 'Đốm mắt cua (Cercospora)',
  'Miner'     : 'Sâu đục lá (Leaf miner)',
  'Phoma'     : 'Thán thư (Phoma)',
  'Rust'      : 'Rỉ sắt lá (Rust)',
  'Healthy'   : 'Lá khoẻ mạnh',
};

/// Hướng dẫn chi tiết (chia 2 nhóm: xử lý nhanh + phòng ngừa lâu dài)
const Map<String, Map<String, List<String>>> kGuide = {
  'Cercospora': {
    'quick': [
      'Tỉa thông thoáng tán, thu gom lá bệnh đem tiêu huỷ.',
      'Hạn chế tưới mưa nhân tạo vào chiều tối.',
      'Phun luân phiên đồng/Mancozeb theo khuyến cáo.',
    ],
    'long': [
      'Bón cân đối N-P-K + vi lượng; tránh thừa đạm.',
      'Chọn giống/ dòng khoẻ, ít mẫn cảm nếu có.',
    ],
  },
  'Miner': {
    'quick': [
      'Ngắt lá bị nặng; đặt bẫy vàng dính.',
      'Phun Abamectin/Spinosad lúc sâu non (chiều mát).',
    ],
    'long': [
      'Bảo tồn thiên địch; hạn chế lạm dụng thuốc.',
      'Quản lý ẩm độ tán hợp lý.',
    ],
  },
  'Phoma': {
    'quick': [
      'Cắt bỏ phần lá/cành bệnh; vệ sinh vườn.',
      'Phun Copper/Fosetyl-Al/Propineb theo nhãn, xoay tua hoạt chất.',
    ],
    'long': [
      'Không tưới ướt tán ban đêm; giảm ẩm độ kéo dài.',
      'Tăng cường dinh dưỡng cân đối để cây khoẻ.',
    ],
  },
  'Rust': {
    'quick': [
      'Tỉa lá gốc, thu gom lá có ổ phấn cam; tiêu huỷ.',
      'Giảm ẩm tán; tránh tưới phun mưa buổi chiều.',
      'Phun Triazole (propiconazole/difenoconazole) hoặc Strobilurin (azoxystrobin) theo nhãn.',
    ],
    'long': [
      'Chọn giống/ dòng chống chịu (nếu có).',
      'Quản lý bóng râm hợp lý, mật độ vừa phải.',
      'Lên lịch phun phòng trước đỉnh dịch (đầu mùa mưa), luân phiên cơ chế.',
    ],
  },
  'Healthy': {
    'quick': ['Không phát hiện bất thường đáng kể.'],
    'long': [
      'Duy trì tưới tiêu hợp lý, bón phân cân đối.',
      'Theo dõi định kỳ để phát hiện sớm.',
    ],
  },
};

class ResultPage extends StatefulWidget {
  static const routeName = '/result';
  const ResultPage({super.key});

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  // trạng thái mở/đóng từng panel
  final Map<String, bool> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final args = (ModalRoute.of(context)?.settings.arguments ?? {}) as Map;
    final String? rawPath              = args['rawPath'] as String?;
    final Uint8List? annotated         = args['annotated'] as Uint8List?;
    final Map<String, dynamic>? detMap = args['detections'] as Map<String, dynamic>?;

    final latencyStr = (detMap?['latency_ms'] is num)
        ? (detMap!['latency_ms'] as num).toStringAsFixed(2)
        : '-';

    // gộp theo bệnh, lấy score cao nhất
    final byClass = _bestScoreByClass(detMap);
    final overall = _pickBestOverall(byClass);

    // thời gian hiển thị + lưu lịch sử
    final now = DateTime.now();
    final timeStr =
        '${_dd(now.day)}/${_dd(now.month)}/${now.year} '
        '${_dd(now.hour)}:${_dd(now.minute)}:${_dd(now.second)}';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFE9F1E9),
        foregroundColor: Colors.black87,
        title: const Text('Kết quả nhận diện'),
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

      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.save_alt),
        label: const Text('Lưu kết quả'),
        onPressed: () async {
          final record = <String, dynamic>{
            'path'   : rawPath,
            'cls'    : overall != null ? (kDiseaseVI[overall.$1] ?? overall.$1) : '—',
            'score'  : overall != null ? overall.$2.toStringAsFixed(2) : '0.00',
            'time'   : timeStr,
            'latency': latencyStr,
          };
          await DetectionHistoryStorage.addRecord(record);
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('✅ Đã lưu vào lịch sử')));
        },
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ảnh
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 3 / 4,
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

          _infoTile(Icons.schedule, 'Ngày giờ nhận diện', timeStr),
          _infoTile(Icons.speed, 'Thời gian xử lý', '$latencyStr ms'),
          const SizedBox(height: 8),

          const Text('Bệnh phát hiện', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),

          if (byClass.isEmpty)
            const Text('Không có phát hiện nào.'),
          if (byClass.isNotEmpty)
            _buildExpansionList(byClass),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ---------- UI helpers ----------
  Widget _buildExpansionList(Map<String, double> byClass) {
    final items = byClass.entries
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value)); // bệnh mạnh nhất lên đầu

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionPanelList.radio(
        elevation: 1,
        expandedHeaderPadding: EdgeInsets.zero,
        materialGapSize: 8,
        animationDuration: const Duration(milliseconds: 250),
        children: items.map((e) {
          final en = e.key;
          final vi = kDiseaseVI[en] ?? en;
          final pct = (e.value * 100).clamp(0, 100).toStringAsFixed(2);
          final guide = kGuide[en] ?? {'quick': <String>[], 'long': <String>[]};
          final quick = guide['quick'] ?? const <String>[];
          final long  = guide['long']  ?? const <String>[];

          return ExpansionPanelRadio(
            value: en,
            headerBuilder: (_, isOpen) => ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFFCEBEA),
                foregroundColor: const Color(0xFFD0544D),
                child: Text(vi.characters.first.toUpperCase()),
              ),
              title: Text(vi, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Độ tin cậy: $pct%'),
            ),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('Xử lý nhanh'),
                  ...quick.map((t) => _bullet(t)).toList(),
                  const SizedBox(height: 12),
                  const _SectionTitle('Phòng ngừa lâu dài'),
                  ...long.map((t) => _bullet(t)).toList(),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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

  // ---------- logic helpers ----------
  Map<String, double> _bestScoreByClass(Map<String, dynamic>? det) {
    final list = (det?['detections'] as List?) ?? const [];
    final Map<String, double> best = {};
    for (final m in list) {
      final cls = (m['cls'] ?? '').toString();
      final sc  = (m['score'] is num) ? (m['score'] as num).toDouble() : 0.0;
      if (!best.containsKey(cls) || sc > best[cls]!) best[cls] = sc;
    }
    return best;
  }

  (String, double)? _pickBestOverall(Map<String, double> bestByClass) {
    String? k; double v = -1;
    bestByClass.forEach((cls, sc) { if (sc > v) { v = sc; k = cls; } });
    return k == null ? null : (k!, v);
  }

  String _dd(int n) => n.toString().padLeft(2, '0');
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}
