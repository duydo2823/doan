import 'package:flutter/material.dart';

class IntroPage extends StatelessWidget {
  const IntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 🎨 Palette
    const bgPage   = Color(0xFFF7F8FA); // nền trung tính sáng
    const textMain = Color(0xFF3F4742); // chữ nội dung
    const primary  = Color(0xFF2E7D32); // xanh lá chủ đạo
    const headline = Color(0xFF1E7D45); // xanh đậm hơn cho tiêu đề
    const border   = Color(0xFFE6E9ED); // viền card rất nhẹ

    return Scaffold(
      backgroundColor: bgPage,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ====== LOGO TO & CÂN BẰNG Ở TRÊN CÙNG ======
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Image.asset(
                            'assets/iuh_logo.png',
                            height: 140, // cao bằng nhau
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Image.asset(
                            'assets/fet_logo.png',
                            height: 140,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ====== CARD TRẮNG, VIỀN NHẸ ======
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: border, width: 1),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x12000000),
                          blurRadius: 14,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                    child: Column(
                      children: [
                        Text(
                          'HỆ THỐNG GIÁM SÁT BỆNH CÂY CÀ PHÊ ỨNG DỤNG THỊ GIÁC MÁY TÍNH VÀ IOT',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            height: 1.32,
                            fontWeight: FontWeight.w800,
                            color: headline,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Ứng dụng Flutter kết hợp ROS2 và YOLOv8 để phát hiện bệnh trên lá cà phê theo thời gian thực.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15.5,
                            height: 1.46,
                            color: textMain,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 22),

                        // ====== NÚT HÀNH ĐỘNG ======
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => Navigator.pushNamed(context, '/detect'),
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('Bắt đầu nhận diện'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => Navigator.pushNamed(
                                  context,
                                  '/solution',
                                  arguments: {'showAll': true},
                                ),
                                icon: const Icon(Icons.list_alt),
                                label: const Text('Xem tất cả bệnh'),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: primary, width: 1.2),
                                  foregroundColor: primary,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
