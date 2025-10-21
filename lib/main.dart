import 'package:flutter/material.dart';
import 'pages/detect_intro_page.dart';
import 'pages/camera_page.dart';
import 'pages/result_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Camera Flow Demo',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const HomePage(),
        DetectIntroPage.routeName: (_) => const DetectIntroPage(),
        CameraPage.routeName: (_) => const CameraPage(),
        ResultPage.routeName: (_) => const ResultPage(),
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trang đầu')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Nhấn BẮT ĐẦU NHẬN DIỆN để chuyển sang Trang 2.\nSau đó nhấn BẮT ĐẦU CHỤP để mở camera.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Bắt đầu nhận diện'),
                onPressed: () =>
                    Navigator.pushNamed(context, DetectIntroPage.routeName),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
