import 'package:flutter/material.dart';

abstract final class AppColors {
  const AppColors._();

  // Marca
  static const Color primary = Color(0xFF2E7D32);
  static const Color accent = Color(0xFF43A047);
  static const Color primaryContainer = Color(0xFFEBF5E9);
  static const Color primaryPressed = Color(0xFF256428);

  // Neutros
  static const Color background = Color(0xFFF6F8F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1A1C1A);
  static const Color textSecondary = Color(0xFF5F6B62);
  static const Color divider = Color(0xFFE6EBE7);

  // Detalhe dourado usado na ilustração de onboarding
  static const Color logoAccent = Color(0xFFC8A13B);
}
