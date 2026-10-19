import 'package:flutter/material.dart';

abstract final class AppColors {
  const AppColors._();

  // Marca
  static const Color primary = Color(0xFF2E7D32);
  static const Color accent = Color(0xFF43A047);
  static const Color primaryContainer = Color(0xFFEBF5E9);
  static const Color primaryPressed = Color(0xFF256428);

  /// Fundo de uma linha de lista que precisa de ação (design U1,
  /// [NextStepRow]); mais claro que [primaryContainer].
  static const Color primaryTint = Color(0xFFF5FAF4);

  // Neutros
  static const Color background = Color(0xFFF6F8F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1A1C1A);
  static const Color textSecondary = Color(0xFF5F6B62);
  static const Color divider = Color(0xFFE6EBE7);

  // Detalhe dourado usado na ilustração de onboarding
  static const Color logoAccent = Color(0xFFC8A13B);

  // Marcas externas, só nos botões "Continuar com Google/Facebook"
  // (as regras de marca de cada um pedem as cores oficiais).
  static const Color googleBlue = Color(0xFF4285F4);
  static const Color googleGreen = Color(0xFF34A853);
  static const Color googleYellow = Color(0xFFFBBC05);
  static const Color googleRed = Color(0xFFEA4335);
  static const Color facebookBlue = Color(0xFF1877F2);
}
