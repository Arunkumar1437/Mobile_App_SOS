import 'package:flutter/material.dart';

import 'screens/home_shell.dart';

void main() {
  runApp(const SurakshaApp());
}

class SurakshaApp extends StatelessWidget {
  const SurakshaApp({super.key});

  static const _seed = Color(0xFFC62828);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AK SOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeShell(),
    );
  }
}
