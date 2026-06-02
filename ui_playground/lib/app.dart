import 'package:flutter/material.dart';
import 'package:ui_playground/screens/playground_home_screen.dart';
import 'package:ui_playground/theme/app_theme.dart';

class PlaygroundApp extends StatelessWidget {
  const PlaygroundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UI Playground',
      theme: AppTheme.light(),
      home: const PlaygroundHomeScreen(),
    );
  }
}
