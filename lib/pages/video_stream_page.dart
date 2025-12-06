import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../services/rosbridge_client.dart';

class VideoStreamPage extends StatefulWidget {
  static const routeName = "/video-stream";

  const VideoStreamPage({super.key});

  @override
  State<VideoStreamPage> createState() => _VideoStreamPageState();
}

class _VideoStreamPageState extends State<VideoStreamPage> {
  late RosbridgeClient _ros;

  Uint8List? _frame;                         // video frame từ ROS
  Map<String, dynamic>? _detections;         // json bbox từ ROS
  String _status = "Disconnected";

  @override
  void initState() {
    super.initState();

    _ros = RosbridgeClient(
      url: "ws://192.168.1.251:9090",
      onStatus: (s) => setState(() => _status = s),

      onAnnotatedFrame: (jpeg) {
        setState(() => _frame = jpeg);
      },

      onDetections: (j) {
        setState(() => _detections = j);
      },
    );

    _ros.connect();
  }

  @override
  void dispose() {
    _ros.disconnect();
    super.dispose();
  }

  Widget _buildVideo() {
    if (_frame == null) {
      return const Center(
        child: Text("Đang chờ video từ ROS...", style: TextStyle(color: Colors.white)),
      );
    }

    return Image.memory(
      _frame!,
      gaplessPlayback: true,
      fit: BoxFit.cover,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ROS Video Stream")),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // VIDEO TỪ ROS
            _buildVideo(),

            // OVERLAY BBOX
            if (_detections != null)
              CustomPaint(
                painter: BboxPainter(json: _detections!),
              ),

            // STATUS
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.all(6),
                color: Colors.black54,
                child: Text(
                  _status,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

/// PAINTER VẼ BOUNDING BOX
class BboxPainter extends CustomPainter {
  final Map<String, dynamic> json;

  BboxPainter({required this.json});

  @override
  void paint(Canvas canvas, Size size) {
    if (!json.containsKey("detections")) return;

    final list = json["detections"];
    if (list is! List) return;

    final imgW = json["image"]["width"] * 1.0;
    final imgH = json["image"]["height"] * 1.0;

    final scaleX = size.width / imgW;
    final scaleY = size.height / imgH;

    final rectPaint = Paint()
      ..color = const Color(0xFF00FF00)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final bgPaint = Paint()..color = const Color(0x88000000);

    for (final raw in list) {
      final box = List<double>.from(raw["bbox"]);
      final cls = raw["cls"];
      final score = raw["score"];

      final x1 = box[0] * scaleX;
      final y1 = box[1] * scaleY;
      final x2 = box[2] * scaleX;
      final y2 = box[3] * scaleY;

      canvas.drawRect(Rect.fromLTRB(x1, y1, x2, y2), rectPaint);

      final text = "$cls ${(score * 100).toStringAsFixed(1)}%";

      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final bg = Rect.fromLTWH(x1, y1 - tp.height - 4, tp.width + 4, tp.height + 2);

      canvas.drawRect(bg, bgPaint);
      tp.paint(canvas, Offset(bg.left + 2, bg.top + 1));
    }
  }

  @override
  bool shouldRepaint(covariant BboxPainter oldDelegate) {
    return true;
  }
}
