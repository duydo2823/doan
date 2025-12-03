import 'package:flutter/material.dart';
import 'pages/detect_intro_page.dart';
import 'pages/result_page.dart';
import 'pages/history_page.dart'; // ✅ Trang lịch sử
import 'pages/video_stream_page.dart'; // ✅ TRANG STREAM MỚI

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Coffee Leaf Disease Detector',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2E7D32),
        scaffoldBackgroundColor: const Color(0xFFF4F8F5),
        fontFamily: 'Roboto',
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const HomePage(),
        DetectIntroPage.routeName: (_) => const DetectIntroPage(),
        ResultPage.routeName: (_) => const ResultPage(),
        '/history': (_) => const HistoryPage(), // ✅ Route cho trang lịch sử
        VideoStreamPage.routeName: (_) => const VideoStreamPage(), // ✅ Route trang stream
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
          children: [
            // Thanh logo
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
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HỆ THỐNG NHẬN DIỆN BỆNH TRÊN LÁ CÀ PHÊ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.green.shade800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Ứng dụng thị giác máy tính và IoT để hỗ trợ người nông dân phát hiện sớm các bệnh trên lá cà phê.',
                      style: TextStyle(fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Icon(Icons.sensors, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Kết nối với cụm xử lý Jetson Nano / ROS2 để nhận diện thời gian thực.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.history_rounded, color: Colors.brown.shade400),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Lưu lại lịch sử các lần nhận diện để theo dõi tình trạng vườn cây.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
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

                    // 🔹 Nút xem lịch sử
                    OutlinedButton.icon(
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('Lịch sử nhận diện'),
                      onPressed: () => Navigator.pushNamed(context, '/history'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        foregroundColor: Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Khoa Công nghệ Điện tử – Trường ĐH Công nghiệp TP.HCM',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
