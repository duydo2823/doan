import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/history_storage.dart';

/// Map tên bệnh hiển thị tiếng Việt
const Map<String, String> kDiseaseVI = {
  'Cercospora': 'Đốm mắt cua (Cercospora)',
  'Miner': 'Sâu đục lá (Leaf miner)',
  'Phoma': 'Đốm lá (Phoma)',
  'Rust': 'Rỉ sắt lá (Rust)',
  'Healthy': 'Lá khoẻ mạnh',
};

/// Hướng dẫn điều trị & phòng ngừa theo tài liệu bạn gửi
const Map<String, Map<String, List<String>>> kGuide = {
  'Miner': {
    'quick': [
      'Khi phát hiện sâu, cắt bỏ cành/thân bị đục và tiêu hủy ngay (cắt xa vị trí đục ≥ 8 cm).',
      'Không cắt được thì dùng dây thép luồn vào lỗ đục để diệt sâu.',
      'Phun thuốc có hoạt chất Diazinon hoặc Chlorpyrifos Ethyl + Cypermethrin theo khuyến cáo.',
      'Phun vào sáng sớm/chiều mát, tập trung vào thân; ưu tiên thuốc độc tính thấp.',
      'Dùng bẫy đèn bắt sâu trưởng thành vào đầu mùa mưa.',
    ],
    'long': [
      'Thăm vườn thường xuyên để phát hiện sớm; cắt bỏ và tiêu hủy cành bệnh.',
      'Vệ sinh vườn, dọn cỏ, đốt bỏ tàn dư thực vật.',
      'Mật độ trồng hợp lý, tỉa cành tạo tán cho thông thoáng.',
      'Bón phân cân đối; tránh lạm dụng đạm; tăng sức đề kháng cho cây.',
      'Bảo vệ thiên địch (ong ký sinh, bọ rùa…).',
      'Dùng chế phẩm sinh học: nấm xanh (Metarhizium), nấm trắng (Beauveria).',
      'Phun phòng định kỳ bằng thuốc thấm sâu/lưu dẫn mạnh.',
      'Có thể bơm thuốc trực tiếp vào lỗ đục bằng xilanh để tăng hiệu quả.',
    ],
  },

  'Rust': {
    'quick': [
      'Kiểm tra vườn thường xuyên để phát hiện sớm.',
      'Phun sớm khi mới chớm: Propiconazole, Difenoconazole, Hexaconazole hoặc Copper Oxychloride.',
      'Phun phòng 10–15 ngày/lần đầu mùa mưa để chặn lây lan.',
      'Thu gom, tiêu hủy lá bệnh; cây nặng thì xử lý riêng, tránh phát tán bào tử.',
      'Luân phiên hoạt chất để tránh kháng thuốc.',
    ],
    'long': [
      'Thu gom, đốt/chôn sâu lá bệnh rụng dưới gốc.',
      'Dọn sạch cỏ dại, tàn dư thực vật.',
      'Trồng mật độ hợp lý, không quá dày; tỉa cành tăm, cành vô hiệu.',
      'Cải thiện thoát nước, giữ vườn khô ráo mùa mưa.',
      'Bón cân đối, tăng Kali; hạn chế bón thừa đạm.',
      'Bổ sung hữu cơ để cải tạo đất và tăng đề kháng.',
    ],
  },

  'Phoma': {
    'quick': [
      'Cắt bỏ lá/cành bệnh nặng để ngăn lây lan và tiêu hủy ngay.',
      'Phun Mancozeb, Copper Oxychloride, Validamycin hoặc Metalaxyl đúng liều.',
      'Dùng chế phẩm sinh học Trichoderma để khống chế nấm trong đất.',
      'Có thể rải vôi bột khử khuẩn đất tại vùng ổ dịch.',
    ],
    'long': [
      'Tỉa cành tạo tán thông thoáng, giảm ẩm vườn.',
      'Vệ sinh vườn, thu gom và tiêu hủy tàn dư, cỏ dại.',
      'Khoảng cách trồng hợp lý để lưu thông ánh sáng/không khí.',
      'Bón cân đối, ưu tiên Kali/Canxi/Silic để tăng đề kháng; tránh thừa đạm.',
      'Tưới tiêu hợp lý, tránh úng hoặc khô hạn kéo dài.',
    ],
  },

  'Cercospora': {
    'quick': [
      'Tỉa bỏ lá, cành, quả bệnh và tiêu hủy xa khu trồng.',
      'Phun Hexaconazole, Copper Hydroxide… theo hướng dẫn; luân phiên hoạt chất.',
      'Có thể dùng Trichoderma/Chaetomium (sinh học) để hỗ trợ.',
      'Sau xử lý, chăm sóc phục hồi: bón cân đối, tưới hợp lý.',
    ],
    'long': [
      'Tỉa cành già/yếu/chen chúc để tăng thông thoáng.',
      'Thu gom, tiêu hủy lá rụng/tàn dư – cắt nguồn nấm bệnh.',
      'Không trồng quá dày, cải thiện thông khí và ánh sáng.',
      'Đảm bảo thoát nước tốt, tránh úng mùa mưa.',
      'Bón cân đối, ưu tiên Kali/Canxi; hạn chế thừa đạm trong mùa mưa.',
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
  // Dữ liệu nhận qua arguments
  String? _rawPath;
  Uint8List? _annotated;
  Map<String, dynamic>? _detections;

  // Tính toán
  late final DateTime _ts = DateTime.now();
  double? _latencyMs;

  // Chỉ lưu lịch sử 1 lần
  bool _saved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    _rawPath   = args?['rawPath'] as String?;
    _annotated = args?['annotated'] as Uint8List?;
    _detections = args?['detections'] as Map<String, dynamic>?;

    if (_detections != null && _detections!['latency_ms'] is num) {
      _latencyMs = (_detections!['latency_ms'] as num).toDouble();
    }

    if (!_saved) {
      _saveHistoryBest();
      _saved = true;
    }
  }

  /// Lấy mỗi bệnh 1 kết quả tốt nhất (điểm cao nhất)
  List<_OneDetection> _bestPerDisease() {
    final list = <_OneDetection>[];
    if (_detections == null) return list;

    final dets = _detections!['detections'];
    if (dets is! List) return list;

    final byClass = <String, _OneDetection>{};
    for (final raw in dets) {
      final m = Map<String, dynamic>.from(raw as Map);
      final cls = (m['cls'] ?? '').toString();
      final score = (m['score'] is num) ? (m['score'] as num).toDouble() : 0.0;
      final bbox = (m['bbox'] as List?)?.map((e) => (e as num).toDouble()).toList();

      if (cls.isEmpty) continue;

      final current = byClass[cls];
      if (current == null || score > current.score) {
        byClass[cls] = _OneDetection(cls: cls, score: score, bbox: bbox);
      }
    }
    list.addAll(byClass.values);
    // Sắp xếp giảm dần theo score
    list.sort((a, b) => b.score.compareTo(a.score));
    return list;
  }

  /// Lưu bản ghi mạnh nhất vào lịch sử
  Future<void> _saveHistoryBest() async {
    final best = _bestPerDisease();
    if (best.isEmpty) return;

    final top = best.first;
    final vi = kDiseaseVI[top.cls] ?? top.cls;
    final imgPath = _rawPath; // lưu path ảnh gốc (nếu có)

    await DetectionHistoryStorage.addRecord({
      'time'   : DateFormat('dd/MM/yyyy HH:mm:ss').format(_ts),
      'cls'    : vi,
      'score'  : top.score.toStringAsFixed(2),
      'latency': _latencyMs?.toStringAsFixed(2) ?? '-',
      'path'   : imgPath,
    });
  }

  @override
  Widget build(BuildContext context) {
    final best = _bestPerDisease();
    final hasAnyImage = _annotated != null || (_rawPath != null && File(_rawPath!).existsSync());

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFE8F0E8),
        title: const Text('Kết quả nhận diện'),
      ),
      backgroundColor: const Color(0xFFF4F8F5),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // Ảnh hiển thị
            if (hasAnyImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Container(
                    color: Colors.white,
                    child: _annotated != null
                        ? Image.memory(_annotated!, fit: BoxFit.contain)
                        : Image.file(File(_rawPath!), fit: BoxFit.contain),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Thông tin thời gian & latency
            _InfoChips(
              time: DateFormat('dd/MM/yyyy HH:mm:ss').format(_ts),
              latency: _latencyMs != null ? '${_latencyMs!.toStringAsFixed(2)} ms' : '—',
            ),

            const SizedBox(height: 16),

            const _SectionTitle('Bệnh phát hiện'),

            if (best.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Không có đối tượng nào được phát hiện.')),
              ),

            // Mỗi bệnh 1 card có thể thu gọn / mở ra
            for (final d in best) _DiseaseCard(detection: d),
          ],
        ),
      ),
    );
  }
}

/* --------------------------------------------------------------- */
/*  Widgets nhỏ                                                     */
/* --------------------------------------------------------------- */

class _InfoChips extends StatelessWidget {
  final String time;
  final String latency;
  const _InfoChips({required this.time, required this.latency});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: [
        Chip(
          avatar: const Icon(Icons.schedule, size: 18),
          label: Text('Thời gian: $time'),
        ),
        Chip(
          avatar: const Icon(Icons.timelapse, size: 18),
          label: Text('Xử lý: $latency'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6EE),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87),
      ),
    );
  }
}

class _DiseaseCard extends StatelessWidget {
  final _OneDetection detection;
  const _DiseaseCard({required this.detection});

  String _leadingLetter(String cls) => (cls.isNotEmpty) ? cls[0].toUpperCase() : '?';

  @override
  Widget build(BuildContext context) {
    final cls = detection.cls;
    final vi = kDiseaseVI[cls] ?? cls;
    final tips = kGuide[cls];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Theme( // làm ExpansionTile ít trống hơn
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: Colors.green.shade50,
            foregroundColor: Colors.green.shade800,
            child: Text(_leadingLetter(cls)),
          ),
          title: Text(
            vi,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          subtitle: Text('Độ tin cậy: ${(detection.score * 100).toStringAsFixed(2)}%'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Divider(),
            if (tips == null)
              const Text('Chưa có hướng dẫn cho bệnh này.'),
            if (tips != null) ...[
              const Text('Xử lý nhanh', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final line in tips['quick']!) _Bullet(line),
              const SizedBox(height: 12),
              const Text('Phòng ngừa lâu dài', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final line in tips['long']!) _Bullet(line),
            ],
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// Model đơn giản cho 1 detection (đã rút gọn)
class _OneDetection {
  final String cls;
  final double score;
  final List<double>? bbox;
  const _OneDetection({required this.cls, required this.score, this.bbox});
}
