import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_typography.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final base = ThemeData(useMaterial3: true);
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).copyWith(
        displaySmall: GoogleFonts.plusJakartaSans(textStyle: AppTypography.display),
        titleLarge: GoogleFonts.plusJakartaSans(textStyle: AppTypography.title),
        titleMedium: GoogleFonts.plusJakartaSans(textStyle: AppTypography.subtitle),
        bodyMedium: GoogleFonts.plusJakartaSans(textStyle: AppTypography.body),
        labelMedium: GoogleFonts.plusJakartaSans(textStyle: AppTypography.caption),
      ),
    );
  }
}
