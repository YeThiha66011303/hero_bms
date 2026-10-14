import 'package:flutter/material.dart';

import 'ui/intro_screen.dart';
import 'ui/scan_screen.dart';

void main() {
  runApp(const HeroBmsApp());
}

class HeroBmsApp extends StatelessWidget {
  const HeroBmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00A884), brightness: b),
          cardTheme: const CardThemeData(elevation: 0),
        );

    return MaterialApp(
      title: 'HERO BMS',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: IntroScreen(next: (_) => const ScanScreen()),
    );
  }
}
