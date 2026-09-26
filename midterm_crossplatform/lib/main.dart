import 'package:flutter/material.dart';

import 'features/analyzer/presentation/analyzer_page.dart';

void main() {
  runApp(const CrossProcessingApp());
}

class CrossProcessingApp extends StatelessWidget {
  const CrossProcessingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cross Processing Lab',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF167C70)),
        useMaterial3: true,
      ),
      home: const AnalyzerPage(),
    );
  }
}
