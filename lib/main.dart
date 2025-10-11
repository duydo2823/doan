// lib/main.dart
import 'package:flutter/material.dart';
import 'intro_page.dart';
import 'detection_page.dart';
import 'solution_page.dart';

void main() {
  runApp(const CoffeeApp());
}

class CoffeeApp extends StatelessWidget {
  const CoffeeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coffee Leaf Disease Detector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),

      // Trang đầu tiên khi mở app
      initialRoute: '/',

      // Đăng ký routes
      routes: {
        '/': (context) => const IntroPage(),
        '/detect': (context) => const DetectionPage(),
        // SolutionPage là StatefulWidget => KHÔNG dùng const
        '/solution': (context) => const SolutionPage(),
        // Nếu trình biên dịch cảnh báo vì kiểu StatefulWidget,
        // hãy dùng dòng dưới thay thế:
        // '/solution': (context) => SolutionPage(),
      },
    );
  }
}
