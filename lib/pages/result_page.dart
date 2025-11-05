// lib/pages/result_page.dart
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';

/// Map tên bệnh hiển thị tiếng Việt
const Map<String, String> kDiseaseVI = {
  'Cercospora': 'Đốm mắt cua (Cercospora)',
  'Miner': 'Sâu đục lá (Leaf miner)',
  'Phoma': 'Thán thư (Phoma)',
  'Rust': 'Rỉ sắt lá (Rust)',
  'Healthy': 'Lá khoẻ mạnh',
};

/// Hướng dẫn xử lý & phòng ngừa (rút gọn, thực hành nông hộ)
/// Lưu ý: Tùy giống/điều kiện địa phương, hãy đối chiếu khuyến cáo khuyến nông
const Map<String, Map<String, List<String>>> kDiseaseGuide = {
  'Cercospora': {
    'Xử lý nhanh': [
      'Tỉa bỏ lá bị đốm nặng, thu gom tiêu huỷ xa vườn.',
      'Giảm tưới/ẩm lá vào chiều tối; tăng thông thoáng tán.',
      'Phun phòng–trị theo nhãn (xoay nhóm hoạt chất): strobilurin, triazole, đồng.',
    ],
    'Phòng ngừa lâu dài': [
      'Bón cân đối N–P–K, bổ sung Ca, Mg, vi lượng; tránh thừa đạm.',
      'Tỉa cành tạo tán, giảm ẩm độ lá, vệ sinh cỏ dại.',
      'Theo dõi đầu mùa mưa để phun phòng sớm.',
    ],
  },
  'Miner': {
    'Xử lý nhanh': [
      'Ngắt bỏ lá bị hại nặng (đường hầm trắng); tiêu huỷ.',
      'Dùng bẫy dính vàng theo dõi trưởng thành.',
      'Phun theo nhãn (xoay nhóm): abamectin, spinosad, emamectin, cyantraniliprole.',
    ],
    'Phòng ngừa lâu dài': [
      'Tăng thiên địch bằng đa dạng sinh học bờ lô.',
      'Không lạm dụng 1 hoạt chất; luân phiên để tránh kháng.',
      'Thu dọn lá rụng, giảm nơi ẩn nấp nhộng/ấu trùng.',
    ],
  },
  'Phoma': { // Anthracnose/Phoma leaf spot
    'Xử lý nhanh': [
      'Cắt tỉa lá/cành bị bệnh, tiêu huỷ.',
      'Giữ tán thông thoáng, hạn chế đọng nước trên lá.',
      'Phun theo nhãn: đồng hydroxide/oxychloride, mancozeb, triazole.',
    ],
    'Phòng ngừa lâu dài': [
      'Bón phân cân đối, tránh sốc dinh dưỡng.',
      'Phun phòng đầu–giữa mùa mưa; vệ sinh vườn sau thu hoạch.',
      'Chọn giống/nhân giống sạch bệnh nếu có.',
    ],
  },
  'Rust': {
    'Xử lý nhanh': [
      'Tỉa lá dưới gốc, lá có ổ pustule màu cam; thu gom tiêu huỷ.',
      'Giảm ẩm tán, tránh tưới phun mưa vào chiều muộn.',
      'Phun theo nhãn: triazole (propiconazole, difenoconazole), strobilurin (azoxystrobin) hoặc phối hợp.',
    ],
    'Phòng ngừa lâu dài': [
      'Trồng giống/ dòng có mức chống chịu tốt (nếu sẵn có địa phương).',
      'Quản lý bóng râm hợp lý, mật độ vừa phải.',
      'Lên lịch phun phòng trước đỉnh dịch (đầu mùa mưa), luân phiên nhóm cơ chế.',
    ],
  },
  'Healthy': {
    'Khuyến nghị chăm sóc': [
      'Duy trì tán thông thoáng, bón phân cân đối.',
      'Theo dõi định kỳ, phát hiện sớm là chìa khoá.',
      'Vệ sinh vườn sau mưa lớn/thu hoạch, giảm nguồn lây.',
    ],
  }
};

class ResultPage extends StatelessWidget {
  static const routeName = '/result';
  const ResultPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map?;
    final String? rawPath = args?['rawPath'] as String?;
    final Uint8List? annotated = args?['annotated'] as Uint8List?;
    final Map<String, dynamic>? detections = args?['detections'] as Map<String, dynamic>?;

    // Gom theo bệnh, lấy score cao nhất
    final bestByClass = _pickBestPerClass(detections);

    // Thời điểm hiển thị
    final detectedAt = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kết quả nhận diện'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Thông tin ảnh/ thời gian
          _HeaderPanel(
            detectedAt: detectedAt,
            filePath: rawPath,
            hasAnnotated: annotated != null,
            totalBoxes: (detections?['detections'] as List?)?.length ?? 0,
          ),
          const SizedBox(height: 12),

          // Ảnh hiển thị (ưu tiên annotated)
          _ImagePanel(annotated: annotated, rawPath: rawPath),
          const SizedBox(height: 16),

          // Danh sách bệnh (đã gộp & sắp xếp theo score)
          if (bestByClass.isNotEmpty) ...[
            const Text('Bệnh phát hiện', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final item in bestByClass)
              _DiseaseTile(
                cls: item.cls,
                score: item.score,
                viName: kDiseaseVI[item.cls] ?? item.cls,
                guide: kDiseaseGuide[item.cls],
              ),
          ] else
            _EmptyDetectPanel(),
        ],
      ),
    );
  }

  /// Lấy mỗi lớp (cls) 1 mục với score cao nhất, sắp xếp giảm dần
  List<_BestDetect> _pickBestPerClass(Map<String, dynamic>? det) {
    final List list = (det?['detections'] as List?) ?? const [];
    final Map<String, double> best = {};
    for (final m in list) {
      final cls = (m['cls'] ?? '').toString();
      final s = (m['score'] is num) ? (m['score'] as num).toDouble() : 0.0;
      if (!best.containsKey(cls) || s > best[cls]!) best[cls] = s;
    }
    final out = best.entries
        .map((e) => _BestDetect(cls: e.key, score: e.value))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return out;
  }
}

class _BestDetect {
  final String cls;
  final double score;
  _BestDetect({required this.cls, required this.score});
}

class _HeaderPanel extends StatelessWidget {
  final DateTime detectedAt;
  final String? filePath;
  final bool hasAnnotated;
  final int totalBoxes;

  const _HeaderPanel({
    super.key,
    required this.detectedAt,
    required this.filePath,
    required this.hasAnnotated,
    required this.totalBoxes,
  });

  @override
  Widget build(BuildContext context) {
    final ts = '${_dd(detectedAt.day)}/${_dd(detectedAt.month)}/${detectedAt.year} '
        '${_dd(detectedAt.hour)}:${_dd(detectedAt.minute)}:${_dd(detectedAt.second)}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv('Thời gian', ts),
          const SizedBox(height: 6),
          _kv('Nguồn ảnh', hasAnnotated ? 'Đã annotate' : (filePath ?? '—')),
          const SizedBox(height: 6),
          _kv('Số khung phát hiện', '$totalBoxes'),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Colors.black54))),
        Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
      ],
    );
  }

  String _dd(int n) => n.toString().padLeft(2, '0');
}

class _ImagePanel extends StatelessWidget {
  final Uint8List? annotated;
  final String? rawPath;
  const _ImagePanel({super.key, this.annotated, this.rawPath});

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (annotated != null) {
      child = Image.memory(annotated!, fit: BoxFit.contain);
    } else if (rawPath != null) {
      child = Image.file(File(rawPath!), fit: BoxFit.contain);
    } else {
      child = const Center(child: Text('Chưa có ảnh để hiển thị'));
    }

    return AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: const Color(0xFFF4F6F8),
          child: FittedBox(fit: BoxFit.contain, child: SizedBox(width: 800, height: 600, child: child)),
        ),
      ),
    );
  }
}

class _DiseaseTile extends StatelessWidget {
  final String cls;
  final double score;
  final String viName;
  final Map<String, List<String>>? guide;

  const _DiseaseTile({
    super.key,
    required this.cls,
    required this.score,
    required this.viName,
    required this.guide,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(cls);
    final sections = guide?.entries.toList() ?? const [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Text(viName.characters.first, style: TextStyle(color: color)),
        ),
        title: Text(
          viName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('Độ tin cậy: ${(score * 100).toStringAsFixed(2)}%'),
        children: sections.isEmpty
            ? [
          const SizedBox(height: 6),
          const Text('Chưa có hướng dẫn cụ thể cho nhãn này.',
              style: TextStyle(color: Colors.black54)),
        ]
            : sections.map((e) => _bulletSection(e.key, e.value)).toList(),
      ),
    );
  }

  Widget _bulletSection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 16),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ...items.map((s) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  '),
              Expanded(child: Text(s)),
            ],
          ),
        )),
      ],
    );
  }

  Color _colorFor(String cls) {
    switch (cls) {
      case 'Cercospora':
        return const Color(0xFF7B1FA2);
      case 'Miner':
        return const Color(0xFF2E7D32);
      case 'Phoma':
        return const Color(0xFF0277BD);
      case 'Rust':
        return const Color(0xFFD84315);
      case 'Healthy':
        return const Color(0xFF6A1B9A);
      default:
        return Colors.teal;
    }
  }
}

class _EmptyDetectPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: const Text(
        'Không phát hiện bệnh đáng kể. Tiếp tục theo dõi và chăm sóc vườn theo quy trình chuẩn.',
        style: TextStyle(color: Colors.black87),
      ),
    );
  }
}
