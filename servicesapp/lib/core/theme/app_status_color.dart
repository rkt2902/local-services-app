import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';

enum AppStatusColor {
  waiting(
    background: Color(0xFFFFF3DB),
    foreground: Color(0xFFB87300),
  ),
  info(
    background: Color(0xFFEAF1FF),
    foreground: Color(0xFF3E68B2),
  ),
  success(
    background: AppColors.primaryContainer,
    foreground: AppColors.primary,
  ),
  cancelled(
    background: Color(0xFFFBEAEA),
    foreground: Color(0xFFD1493F),
  ),
  neutral(
    background: Color(0xFFEEF1EE),
    foreground: AppColors.textSecondary,
  );

  const AppStatusColor({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}
