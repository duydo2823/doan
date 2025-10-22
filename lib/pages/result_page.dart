import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl; // ✅ alias để không trùng với TextDirection
import 'dart:ui' show TextDirection; // ✅ lấy TextDirection chuẩn Flutter

import '../services/history_storage.dart';
import 'history_page.dart';

// ✅ Bảng quy đổi tên bệnh
const Map<String, String> kDiseaseVI = {
  'Cercospora': 'Đốm mắt cua (Cercospora)',
  'Miner': 'Sâu đục lá (Leaf miner)',
  'Phoma': 'Thán thư (Phoma)',
  'Rust': 'Rỉ sắt lá (Rust)',
  'Healthy': 'Lá khoẻ mạnh',
};

class ResultPage extends StatelessWidget {
  static const routeName = '/result';
  const ResultPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final String? rawPath = args?['rawPath'] as String?;
    final Uint8List? annotated = args?['annotated'] as Uint8List?;
    final Map<String, dynamic>? det =
    (args?['detections'] as Map?)?.cast<String, dynamic>();

    // --- Parse dữ liệu ---
    final List<Map<String, dynamic>> boxes =
    (det?['detections'] is List) ? List<Map<String, dynamic>>.from(det!['detections']) : [];
    final double? latency =
    (det?['latency_ms'] is num) ? (det!['latency_ms'] as num).toDouble() : null;
    final double? imgW = (det?['image']?['width'] as num?)?.toDouble();
    final double? imgH = (det?['image']?['height'] as num?)?.toDouble();

    // ✅ Lọc trùng — chỉ giữ bệnh có score cao nhất
    final Map<String, Map<String, dynamic>> bestByClass = {};
    for (final b in boxes) {
      final cls = b['cls']?.toString() ?? 'Unknown';
      final score = (b['score'] is num) ? (b['score'] as num).toDouble() : 0.0;
      if (!bestByClass.containsKey(cls) || score > (bestByClass[cls]!['score'] ?? 0.0)) {
        bestByClass[cls] = b;
      }
    }
    final List<Map<String, dynamic>> filteredBoxes = bestByClass.values.toList();

    // --- Ngày giờ ---
    final now = DateTime.now();
    final ts = intl.DateFormat('dd/MM/yyyy HH:mm:ss').format(now);

    // --- Bệnh mạnh nhất để lưu lịch sử ---
    String topCls = 'Không rõ';
    double topScore = 0;
    if (filteredBoxes.isNotEmpty) {
      final best = filteredBoxes.reduce(
              (a, b) => ((a['score'] ?? 0) as num) > ((b['score'] ?? 0) as num) ? a : b);
      topCls = (best['cls'] ?? 'Unknown').toString();
      topScore = ((best['score'] ?? 0) as num).toDouble();
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF43A047),
        foregroundColor: Colors.white,
        title: const Text('Kết quả nhận diện'),
      ),
      backgroundColor: const Color(0xFFF5F8F5),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Ảnh và khung nhận diện ---
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: (imgW != null && imgH != null && imgW > 0 && imgH > 0)
                    ? (imgW / imgH)
                    : 4 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (annotated != null)
                      Image.memory(annotated, fit: BoxFit.contain)
                    else if (rawPath != null)
                      Image.file(File(rawPath), fit: BoxFit.contain)
                    else
                      const ColoredBox(color: Colors.black12),

                    if (annotated == null &&
                        imgW != null &&
                        imgH != null &&
                        filteredBoxes.isNotEmpty)
                      FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: imgW,
                          height: imgH,
                          child: CustomPaint(
                            painter: _BoxesPainter(
                              boxes: filteredBoxes,
                              imageW: imgW,
                              imageH: imgH,
                              label: (m) {
                                final cls = (m['cls'] ?? '').toString();
                                final vi = kDiseaseVI[cls] ?? cls;
                                final score =
                                (m['score'] is num) ? (m['score'] as num).toDouble() : 0.0;
                                return '${vi.split('(').first.trim()} ${score.toStringAsFixed(2)}';
                              },
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // --- Thông tin ---
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.schedule, size: 18),
                    const SizedBox(width: 8),
                    Text('Ngày giờ nhận diện: $ts'),
                  ]),
                  const SizedBox(height: 6),
                  if (latency != null)
                    Row(children: [
                      const Icon(Icons.timer_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text('Thời gian xử lý: ${latency.toStringAsFixed(2)} ms'),
                    ]),
                  const SizedBox(height: 10),
                  const Text('Kết quả phát hiện:',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  if (filteredBoxes.isEmpty)
                    const Text('Không phát hiện bệnh.'),
                  ...filteredBoxes.map((m) {
                    final cls = (m['cls'] ?? '').toString();
                    final vi = kDiseaseVI[cls] ?? cls;
                    final score =
                    (m['score'] is num) ? (m['score'] as num).toDouble() : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.local_florist, size: 18, color: Color(0xFF43A047)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$vi',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(score.toStringAsFixed(2)),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // --- Nút lưu / lịch sử / về trang đầu ---
            FilledButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Lưu kết quả'),
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () async {
                await DetectionHistoryStorage.addRecord({
                  'time': ts,
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
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.history),
              label: const Text('Xem lịch sử nhận diện'),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()));
              },
            ),
            const SizedBox(height: 8),
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

  Widget _card(Widget child) {
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

/// Vẽ khung bbox (nếu không có annotated image)
class _BoxesPainter extends CustomPainter {
  _BoxesPainter({
    required this.boxes,
    required this.imageW,
    required this.imageH,
    required this.label,
  });

  final List<Map<String, dynamic>> boxes;
  final double imageW, imageH;
  final String Function(Map<String, dynamic>) label;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF00BCD4);

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xAA00BCD4);

    for (final m in boxes) {
      final bb = (m['bbox'] as List?)?.map((e) => (e as num).toDouble()).toList();
      if (bb == null || bb.length < 4) continue;

      final rect = Rect.fromLTRB(bb[0], bb[1], bb[2], bb[3]);
      canvas.drawRect(rect, stroke);

      final textSpan = TextSpan(
        text: label(m),
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      tp.layout();

      const pad = 4.0;
      final labelRect = Rect.fromLTWH(
        rect.left,
        rect.top - (tp.height + pad * 2),
        tp.width + pad * 2,
        tp.height + pad * 2,
      );
      canvas.drawRect(labelRect, fill);
      tp.paint(canvas, Offset(labelRect.left + pad, labelRect.top + pad));
    }
  }

  @override
  bool shouldRepaint(covariant _BoxesPainter old) =>
      old.boxes != boxes || old.imageW != imageW || old.imageH != imageH;
}
