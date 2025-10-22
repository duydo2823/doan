import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class ResultPage extends StatefulWidget {
  static const routeName = '/result';
  const ResultPage({super.key});

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  String? _rawPath;
  Uint8List? _annotatedBytes;
  Map<String, dynamic>? _detections;

  // Kích thước ảnh gốc để scale bbox khi không có annotated
  int? _imgW;
  int? _imgH;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _rawPath = args?['rawPath'] as String?;
    _annotatedBytes = args?['annotated'] as Uint8List?;
    _detections = (args?['detections'] as Map?)?.cast<String, dynamic>();

    // Nếu JSON có image_width/height thì dùng luôn
    _imgW = (_detections?['image_width'] as num?)?.toInt();
    _imgH = (_detections?['image_height'] as num?)?.toInt();

    // Nếu chưa có kích thước, decode ảnh gốc để lấy width/height
    if ((_imgW == null || _imgH == null) && _rawPath != null) {
      _decodeImageSize(File(_rawPath!).readAsBytesSync());
    }
  }

  Future<void> _decodeImageSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      setState(() {
        _imgW = frame.image.width;
        _imgH = frame.image.height;
      });
    } catch (_) {
      // ignore
    }
  }

  List<_Det> _parseDetections() {
    final List<_Det> out = [];
    final list = _detections?['detections'];
    if (list is List) {
      for (final d in list) {
        if (d is! Map) continue;
        final label = d['label']?.toString() ?? 'unknown';
        final score = (d['score'] as num?)?.toDouble();
        final bbox = d['bbox'];
        if (bbox is Map) {
          // hỗ trợ 2 format
          if (bbox.containsKey('xmin')) {
            // tuyệt đối (xmin, ymin, xmax, ymax)
            final xmin = (bbox['xmin'] as num?)?.toDouble();
            final ymin = (bbox['ymin'] as num?)?.toDouble();
            final xmax = (bbox['xmax'] as num?)?.toDouble();
            final ymax = (bbox['ymax'] as num?)?.toDouble();
            if (xmin != null && ymin != null && xmax != null && ymax != null) {
              out.add(_Det(label: label, score: score, rectAbs: Rect.fromLTRB(xmin, ymin, xmax, ymax)));
            }
          } else if (bbox.containsKey('x') && bbox.containsKey('y') && bbox.containsKey('w') && bbox.containsKey('h')) {
            // chuẩn hóa (x,y,w,h) nếu normalized=true
            final norm = bbox['normalized'] == true;
            final x = (bbox['x'] as num?)?.toDouble();
            final y = (bbox['y'] as num?)?.toDouble();
            final w = (bbox['w'] as num?)?.toDouble();
            final h = (bbox['h'] as num?)?.toDouble();
            if (x != null && y != null && w != null && h != null) {
              if (norm) {
                out.add(_Det(label: label, score: score, rectNorm: Rect.fromLTWH(x, y, w, h)));
              } else {
                out.add(_Det(label: label, score: score, rectAbs: Rect.fromLTWH(x, y, w, h)));
              }
            }
          }
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final dets = _parseDetections();
    final diseaseNames = <String>{
      for (final d in dets) d.label,
    }.toList();

    final hasAnnotated = _annotatedBytes != null;
    final hasRaw = _rawPath != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Kết quả nhận diện')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Hàng tên bệnh (chips)
            if (diseaseNames.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: diseaseNames
                      .map((e) => Chip(
                    label: Text(e),
                    avatar: const Icon(Icons.local_florist, size: 18),
                  ))
                      .toList(),
                ),
              )
            else
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Chưa phát hiện bệnh.', style: TextStyle(color: Colors.black54)),
              ),
            const SizedBox(height: 8),

            // Khung ảnh (annotated ưu tiên; nếu không có thì ảnh gốc + overlay bbox)
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: hasAnnotated
                    ? Image.memory(_annotatedBytes!, fit: BoxFit.contain)
                    : (hasRaw
                    ? _OverlayImage(
                  imageFile: File(_rawPath!),
                  imgW: _imgW,
                  imgH: _imgH,
                  detections: dets,
                )
                    : const Center(child: Text('Không có ảnh để hiển thị'))),
              ),
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
}

/// Model detection
class _Det {
  _Det({required this.label, this.score, this.rectAbs, this.rectNorm});
  final String label;
  final double? score;
  final Rect? rectAbs;   // bbox theo pixel gốc
  final Rect? rectNorm;  // bbox normalized [0..1]
}

/// Widget hiển thị ảnh gốc + vẽ overlay bbox
class _OverlayImage extends StatelessWidget {
  const _OverlayImage({
    required this.imageFile,
    required this.imgW,
    required this.imgH,
    required this.detections,
  });

  final File imageFile;
  final int? imgW;
  final int? imgH;
  final List<_Det> detections;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      return FutureBuilder<ui.Image>(
        future: _loadImage(imageFile),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final uiImg = snap.data!;
          final srcW = imgW ?? uiImg.width;
          final srcH = imgH ?? uiImg.height;

          // Tính scale để fit contain vào khung c.maxWidth x c.maxHeight
          final boxW = c.maxWidth;
          final boxH = c.maxHeight;
          final scale = _containScale(srcW.toDouble(), srcH.toDouble(), boxW, boxH);
          final drawW = srcW * scale;
          final drawH = srcH * scale;
          final dx = (boxW - drawW) / 2;
          final dy = (boxH - drawH) / 2;

          return Stack(
            children: [
              // Ảnh
              Positioned(
                left: dx,
                top: dy,
                width: drawW,
                height: drawH,
                child: RawImage(image: uiImg, fit: BoxFit.contain),
              ),
              // Overlay bbox
              Positioned.fill(
                child: CustomPaint(
                  painter: _BboxPainter(
                    detections: detections,
                    offset: Offset(dx, dy),
                    scale: scale,
                    srcW: srcW.toDouble(),
                    srcH: srcH.toDouble(),
                  ),
                ),
              ),
            ],
          );
        },
      );
    });
  }

  Future<ui.Image> _loadImage(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static double _containScale(double srcW, double srcH, double dstW, double dstH) {
    final sx = dstW / srcW;
    final sy = dstH / srcH;
    return sx < sy ? sx : sy;
  }
}

/// Vẽ bbox + nhãn
class _BboxPainter extends CustomPainter {
  _BboxPainter({
    required this.detections,
    required this.offset,
    required this.scale,
    required this.srcW,
    required this.srcH,
  });

  final List<_Det> detections;
  final Offset offset;
  final double scale;
  final double srcW;
  final double srcH;

  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in detections) {
      Rect r;
      if (d.rectAbs != null) {
        r = Rect.fromLTRB(
          d.rectAbs!.left * scale + offset.dx,
          d.rectAbs!.top * scale + offset.dy,
          d.rectAbs!.right * scale + offset.dx,
          d.rectAbs!.bottom * scale + offset.dy,
        );
      } else if (d.rectNorm != null) {
        r = Rect.fromLTWH(
          d.rectNorm!.left * srcW * scale + offset.dx,
          d.rectNorm!.top * srcH * scale + offset.dy,
          d.rectNorm!.width * srcW * scale,
          d.rectNorm!.height * srcH * scale,
        );
      } else {
        continue;
      }

      // Màu viền: mặc định theo hash label (để khác nhau)
      _stroke.color = _hashColor(d.label);

      // Vẽ khung
      canvas.drawRect(r, _stroke);

      // Vẽ nhãn nền mờ
      final textSpan = TextSpan(
        text: d.score != null ? '${d.label} ${(d.score!*100).toStringAsFixed(1)}%' : d.label,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
      final pad = 4.0;
      final rectBg = Rect.fromLTWH(r.left, r.top - tp.height - 6, tp.width + pad * 2, tp.height + 4);
      final bgPaint = Paint()..color = _stroke.color.withOpacity(0.8);
      canvas.drawRRect(RRect.fromRectAndRadius(rectBg, const Radius.circular(4)), bgPaint);
      tp.paint(canvas, Offset(rectBg.left + pad, rectBg.top + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _BboxPainter oldDelegate) {
    return oldDelegate.detections != detections || oldDelegate.scale != scale || oldDelegate.offset != offset;
  }

  Color _hashColor(String key) {
    final h = key.codeUnits.fold<int>(0, (p, c) => (p * 31 + c) & 0xFFFFFFFF);
    // tạo màu tươi
    final r = 100 + (h & 0x5F);
    final g = 100 + ((h >> 8) & 0x5F);
    final b = 100 + ((h >> 16) & 0x5F);
    return Color.fromARGB(255, r, g, b);
  }
}
