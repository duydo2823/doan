import 'package:flutter/material.dart';

import 'pages/detect_intro_page.dart';
import 'pages/result_page.dart';
import 'pages/history_page.dart';
import 'pages/video_stream_page.dart'; // ✅ trang stream mới

Future<void> main() async {
  // BẮT BUỘC khi dùng plugin camera / các plugin native khác
  WidgetsFlutterBinding.ensureInitialized();
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
        scaffoldBackgroundColor: const Color(0xFFF4F8F5),
        fontFamily: 'Roboto',
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const HomePage(),
        DetectIntroPage.routeName: (_) => const DetectIntroPage(),
        ResultPage.routeName: (_) => const ResultPage(),
        '/history': (_) => const HistoryPage(),
        VideoStreamPage.routeName: (_) => const VideoStreamPage(), // ✅ route mới
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
            // LOGO trên cùng
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

            // Hộp nội dung chính
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'HỆ THỐNG GIÁM SÁT BỆNH TRÊN CÂY CÀ PHÊ',
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
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Icon(Icons.sensors, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Kết nối cụm xử lý Jetson Nano / ROS2, hỗ trợ nhận diện ảnh tĩnh và stream video.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.history_rounded,
                            color: Colors.brown.shade400),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Lưu lại lịch sử nhận diện để theo dõi tình trạng vườn cà phê.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Nút Bắt đầu nhận diện
                    FilledButton.icon(
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Bắt đầu nhận diện'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      onPressed: () => Navigator.pushNamed(
                        context,
                        DetectIntroPage.routeName,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Nút xem lịch sử
                    OutlinedButton.icon(
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('Lịch sử nhận diện'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        foregroundColor: Colors.green.shade800,
                      ),
                      onPressed: () =>
                          Navigator.pushNamed(context, '/history'),
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
