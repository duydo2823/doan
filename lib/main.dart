import 'package:flutter/material.dart';
import 'pages/detect_intro_page.dart';
import 'pages/result_page.dart';
import 'pages/history_page.dart'; // ✅ Thêm dòng này

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Giám sát bệnh cà phê',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const HomePage(),
        DetectIntroPage.routeName: (_) => const DetectIntroPage(),
        ResultPage.routeName: (_) => const ResultPage(),
        '/history': (_) => const HistoryPage(), // ✅ Route cho trang lịch sử
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F5),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // LOGO trên cùng (sửa đường dẫn assets theo dự án của bạn)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('assets/iuh_logo.png', height: 60),
                  Image.asset('assets/fet_logo.png', height: 60),
                ],
              ),
            ),
            // Hộp nội dung
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'HỆ THỐNG GIÁM SÁT BỆNH\nCÀ PHÊ ỨNG DỤNG THỊ GIÁC MÁY TÍNH VÀ IOT',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Ứng dụng Flutter kết hợp ROS2 và YOLOv8 để phát hiện bệnh trên lá cà phê theo thời gian thực.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.black87, height: 1.4),
                    ),
                    const SizedBox(height: 24),

                    // 🔹 Nút Bắt đầu nhận diện
                    FilledButton.icon(
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Bắt đầu nhận diện'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      onPressed: () =>
                          Navigator.pushNamed(context, DetectIntroPage.routeName),
                    ),
                    const SizedBox(height: 12),

                    // 🔹 Nút Xem tất cả bệnh
                    OutlinedButton.icon(
                      icon: const Icon(Icons.list_alt_outlined),
                      label: const Text('Xem tất cả bệnh'),
                      onPressed: () {
                        Navigator.pushNamed(context, '/history'); // ✅ mở trang lịch sử
                      },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        foregroundColor: Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
