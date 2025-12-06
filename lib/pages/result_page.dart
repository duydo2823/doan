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

/// Hướng dẫn điều trị & phòng ngừa
/// Mỗi bệnh có 2 nhóm:
///   quick   - xử lý nhanh khi đã phát hiện bệnh
///   prevent - phòng ngừa lâu dài
const Map<String, Map<String, List<String>>> kGuide = {
  'Cercospora': {
    'quick': [
      'Tỉa bỏ các lá, cành bị bệnh nặng, thu gom và tiêu hủy để tránh lây lan.',
      'Không để lá bệnh rụng lại trên vườn, hạn chế nước tưới văng làm phát tán bào tử.',
      'Khi bệnh nặng có thể phun thuốc gốc đồng hoặc các thuốc đặc trị theo khuyến cáo của cán bộ kỹ thuật.',
    ],
    'prevent': [
      'Trồng với mật độ hợp lý, tỉa cành tạo tán thông thoáng giúp vườn ít ẩm, hạn chế nấm bệnh.',
      'Bón phân cân đối N-P-K, tăng cường phân hữu cơ và kali để lá dày, khỏe, ít nhiễm bệnh.',
      'Thường xuyên kiểm tra vườn, phát hiện sớm các vết bệnh nhỏ để xử lý kịp thời.',
    ],
  },
  'Miner': {
    'quick': [
      'Cắt bỏ và tiêu hủy các lá, cành bị sâu đục nặng để triệt nguồn sâu.',
      'Khi phát hiện đường đục mới, có thể dùng tay vò nát lá hoặc cắt bỏ phần lá đó.',
      'Có thể sử dụng thuốc trừ sâu theo khuyến cáo địa phương khi mật số cao.',
    ],
    'prevent': [
      'Giữ vườn thông thoáng, hạn chế cỏ dại là nơi trú ẩn của sâu.',
      'Bón phân cân đối, không bón thừa đạm làm lá non ra quá nhiều, dễ thu hút sâu.',
      'Theo dõi thường xuyên vào giai đoạn cây ra đọt non để phát hiện sớm sâu non.',
    ],
  },
  'Phoma': {
    'quick': [
      'Cắt tỉa và tiêu hủy lá, cành bị bệnh, nhất là những lá có nhiều đốm cháy lớn.',
      'Giảm tưới, tránh để vườn ẩm ướt kéo dài vì tạo điều kiện cho nấm phát triển.',
      'Trong trường hợp bệnh nặng có thể phun thuốc trừ nấm theo đúng liều lượng khuyến cáo.',
    ],
    'prevent': [
      'Quản lý tốt tàn dư thực vật, không để cành lá bệnh tồn tại trong vườn.',
      'Bón phân hữu cơ hoai mục kết hợp nấm đối kháng để cải tạo đất và hạn chế nấm gây bệnh.',
      'Tạo tán thông thoáng, hạn chế trồng quá dày, thường xuyên vệ sinh vườn.',
    ],
  },
  'Rust': {
    'quick': [
      'Loại bỏ lá bị bệnh nặng, thu gom và tiêu hủy đúng cách.',
      'Hạn chế tưới phun mưa vào thời điểm chiều tối, tránh làm ẩm kéo dài trên mặt lá.',
      'Khi bệnh phát triển mạnh có thể sử dụng thuốc đặc trị bệnh rỉ sắt theo hướng dẫn.',
    ],
    'prevent': [
      'Chọn giống có khả năng chống chịu bệnh rỉ sắt tốt nếu có điều kiện.',
      'Chăm sóc cân đối dinh dưỡng, tránh bón quá nhiều đạm làm lá non mỏng, dễ nhiễm bệnh.',
      'Theo dõi vườn thường xuyên vào đầu và giữa mùa mưa để phát hiện sớm vết bệnh rỉ.',
    ],
  },
  'Healthy': {
    'quick': [
      'Không phát hiện dấu hiệu bệnh rõ ràng trên lá cà phê ở thời điểm hiện tại.',
      'Tiếp tục theo dõi cây để kịp thời phát hiện nếu xuất hiện triệu chứng bất thường.',
    ],
    'prevent': [
      'Duy trì chăm sóc vườn theo quy trình, bón phân cân đối và tỉa cành hợp lý.',
      'Chủ động vệ sinh vườn, quản lý cỏ dại, thoát nước tốt để hạn chế mầm bệnh phát sinh.',
    ],
  },
};

/// Chuẩn hoá tên lớp bệnh từ ROS về key chuẩn để tra map
String normalizeDiseaseKey(String raw) {
  final s = raw.trim();
  final lower = s.toLowerCase();

  if (lower.contains('cercospora')) return 'Cercospora';
  if (lower.contains('miner')) return 'Miner';
  if (lower.contains('phoma')) return 'Phoma';
  if (lower.contains('rust')) return 'Rust';
  if (lower.contains('healthy') || lower.contains('normal')) return 'Healthy';

  return s;
}

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
  double? _latencyMs;

  bool _initialized = false;
  bool _savedHistory = false;

  final NumberFormat _scoreFormat = NumberFormat('0.0');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;

    final args = ModalRoute.of(context)?.settings.arguments;

    if (args is String) {
      // Trường hợp từ CameraPage: chỉ có đường dẫn ảnh
      _rawPath = args;
    } else if (args is Map) {
      // Trường hợp từ VideoStreamPage: nhận annotated + detections
      final map = Map<String, dynamic>.from(args as Map);
      _rawPath = map['rawPath'] as String?;
      _annotated = map['annotated'] as Uint8List?;
      final det = map['detections'];
      if (det is Map<String, dynamic>) {
        _detections = det;
      } else if (det is Map) {
        _detections = Map<String, dynamic>.from(det);
      }
      final lat = map['latencyMs'];
      if (lat is num) {
        _latencyMs = lat.toDouble();
      }
    }

    _initialized = true;

    // Lưu lịch sử (nếu có detection)
    if (_detections != null && !_savedHistory) {
      _savedHistory = true;
      _saveHistoryBest();
    }
  }

  /// Lấy mỗi bệnh 1 kết quả tốt nhất (score cao nhất)
  List<_OneDetection> _bestPerDisease() {
    final list = <_OneDetection>[];
    if (_detections == null) return list;

    final dets = _detections!['detections'];
    if (dets is! List) return list;

    final byClass = <String, _OneDetection>{};

    for (final raw in dets) {
      final m = Map<String, dynamic>.from(raw as Map);

      final rawCls = (m['cls'] ?? '').toString();
      final cls = normalizeDiseaseKey(rawCls);

      final score =
      (m['score'] is num) ? (m['score'] as num).toDouble() : 0.0;
      final bbox = (m['bbox'] as List?)
          ?.map((e) => (e as num).toDouble())
          .toList();

      if (cls.isEmpty) continue;

      final current = byClass[cls];
      if (current == null || score > current.score) {
        byClass[cls] = _OneDetection(cls: cls, score: score, bbox: bbox);
      }
    }

    list.addAll(byClass.values);
    list.sort((a, b) => b.score.compareTo(a.score));
    return list;
  }

  Future<void> _saveHistoryBest() async {
    final best = _bestPerDisease();
    if (best.isEmpty) return;

    final top = best.first;
    final canonical = normalizeDiseaseKey(top.cls);

    final now = DateTime.now();
    final fmt = DateFormat('dd/MM/yyyy HH:mm:ss');

    final record = <String, dynamic>{
      'time': fmt.format(now),
      'cls': canonical,
      'score': '${_scoreFormat.format(top.score * 100)}%',
      'latency': _latencyMs?.round() ?? 0,
      'path': _rawPath ?? '',
    };

    try {
      await DetectionHistoryStorage.addRecord(record);
    } catch (_) {
      // Bỏ qua lỗi lưu lịch sử để không làm văng app
    }
  }

  @override
  Widget build(BuildContext context) {
    final best = _bestPerDisease();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kết quả chẩn đoán'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildImagePreview(),
              const SizedBox(height: 16),
              if (best.isEmpty)
                const Text(
                  'Không có đối tượng nào được phát hiện hoặc chưa có dữ liệu từ mô hình.',
                  style: TextStyle(fontSize: 14),
                )
              else ...[
                const Text(
                  'Tổng quan',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hệ thống đã chọn ra đối tượng có độ tin cậy cao nhất cho mỗi loại bệnh. '
                      'Bấm vào từng mục để xem hướng dẫn xử lý nhanh và phòng ngừa lâu dài.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                ...best.map((d) => _DiseaseCard(detection: d)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    Widget child;
    if (_annotated != null) {
      child = Image.memory(
        _annotated!,
        fit: BoxFit.contain,
      );
    } else if (_rawPath != null && _rawPath!.isNotEmpty) {
      final file = File(_rawPath!);
      if (file.existsSync()) {
        child = Image.file(
          file,
          fit: BoxFit.contain,
        );
      } else {
        child = const Center(
          child: Text('Không tìm thấy file ảnh gốc.'),
        );
      }
    } else {
      child = const Center(
        child: Text('Chưa có ảnh để hiển thị.'),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey.shade200,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _DiseaseCard extends StatelessWidget {
  final _OneDetection detection;

  const _DiseaseCard({required this.detection});

  String _leadingLetter(String cls) =>
      (cls.isNotEmpty) ? cls[0].toUpperCase() : '?';

  @override
  Widget build(BuildContext context) {
    final canonical = normalizeDiseaseKey(detection.cls);
    final vi = kDiseaseVI[canonical] ?? canonical;
    final tips = kGuide[canonical];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      child: ExpansionTile(
        leading: CircleAvatar(
          child: Text(_leadingLetter(canonical)),
        ),
        title: Text(
          vi,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Độ tin cậy: ${(detection.score * 100).toStringAsFixed(1)}%',
          style: const TextStyle(fontSize: 13),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (tips == null)
            const Text(
              'Chưa có hướng dẫn chi tiết cho bệnh này.',
              style: TextStyle(fontSize: 13),
            )
          else ...[
            if (tips['quick'] != null && tips['quick']!.isNotEmpty)
              _TipSection(
                icon: Icons.medical_services,
                title: 'Xử lý nhanh trên vườn',
                items: tips['quick']!,
              ),
            const SizedBox(height: 8),
            if (tips['prevent'] != null && tips['prevent']!.isNotEmpty)
              _TipSection(
                icon: Icons.shield,
                title: 'Phòng ngừa lâu dài',
                items: tips['prevent']!,
              ),
          ],
        ],
      ),
    );
  }
}

class _TipSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> items;

  const _TipSection({
    required this.icon,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...items.map(
              (e) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ',
                    style: TextStyle(fontSize: 13, height: 1.4)),
                Expanded(
                  child: Text(
                    e,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Model đơn giản cho 1 detection (đã rút gọn)
class _OneDetection {
  final String cls;
  final double score;
  final List<double>? bbox;

  const _OneDetection({
    required this.cls,
    required this.score,
    this.bbox,
  });
}
