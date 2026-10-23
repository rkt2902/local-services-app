import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final base = ThemeData(useMaterial3: true);
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
      // Sem isto, qualquer Scaffold que não defina o seu próprio
      // `backgroundColor` (ex.: o Scaffold do ClientShell/WorkerShell, que
      // só existe para alojar a bottom nav) cai no `colorScheme.surface`
      // gerado pelo Material 3 a partir da seed — uma cor diferente de
      // `AppColors.background`, visível como uma faixa esverdeada distinta
      // por cima da barra de navegação (ver decisions_log.md).
      scaffoldBackgroundColor: AppColors.background,
      // Folhas e diálogos que não passam cor própria caíam no
      // `surfaceContainerLow`/`surfaceContainerHigh` da seed (cinzento
      // esverdeado) em vez do branco do design system. Aqui fica o fundo
      // certo para todos, incluindo os seletores câmara/galeria.
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      timePickerTheme: const TimePickerThemeData(
        backgroundColor: AppColors.surface,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).copyWith(
        displaySmall: GoogleFonts.plusJakartaSans(textStyle: AppTypography.display),
        titleLarge: GoogleFonts.plusJakartaSans(textStyle: AppTypography.title),
        titleMedium: GoogleFonts.plusJakartaSans(textStyle: AppTypography.subtitle),
        bodyMedium: GoogleFonts.plusJakartaSans(textStyle: AppTypography.body),
        labelMedium: GoogleFonts.plusJakartaSans(textStyle: AppTypography.caption),
      ),
    );
  }

  /// Estilo único da UI de sistema (barra de navegação do Android) para a
  /// app toda — aplicado uma só vez em `app.dart` via `AnnotatedRegion`, não
  /// por ecrã. A cor combina com `AppBottomNavigation` (`AppColors.surface`)
  /// para a área do inset de gestos não aparecer com um tom diferente da
  /// barra em nenhum ecrã, dentro ou fora do shell.
  static const systemUiOverlayStyle = SystemUiOverlayStyle(
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
  );
}
