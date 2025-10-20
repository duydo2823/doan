import 'package:app3/detection_page.dart';
import 'package:app3/solution_page.dart';
import 'package:flutter/material.dart';
import 'intro_page.dart'; // hoặc màn hình đầu của bạn

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'App3',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      home: const IntroPage(), // trang đầu tiên
      routes: {
        '/detection': (_) => const DetectionPage(),
        '/solution': (_) =>  SolutionPage(),
      },
    );
  }
}
