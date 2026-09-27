import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// `showDatePicker()` nativo do Flutter, com o tema da app aplicado via
/// `builder` — mesmo widget/comportamento/acessibilidade do date picker do
/// Material (navegação por calendário ou input de texto, leitores de ecrã,
/// etc.), só a pele visual muda. Não é um calendário construído de raiz.
///
/// Substitui todas as chamadas a `showDatePicker()` da app — sem isto, o
/// diálogo usava o `ColorScheme` gerado automaticamente por
/// `ColorScheme.fromSeed` (tom de verde diferente do `AppColors.primary`
/// exato usado no resto da app, cantos a 28px por omissão do M3 em vez dos
/// 16px de `AppRadius.card`).
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    builder: (context, child) {
      final base = Theme.of(context);
      return Theme(
        data: base.copyWith(
          colorScheme: base.colorScheme.copyWith(
            primary: AppColors.primary,
            onPrimary: AppColors.surface,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
          ),
          datePickerTheme: DatePickerThemeData(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            headerBackgroundColor: AppColors.primary,
            headerForegroundColor: AppColors.surface,
            headerHeadlineStyle: base.textTheme.titleLarge?.copyWith(
              color: AppColors.surface,
            ),
            headerHelpStyle: base.textTheme.labelMedium?.copyWith(
              color: AppColors.surface,
            ),
            weekdayStyle: base.textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
            dayStyle: base.textTheme.bodyMedium,
            dayForegroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return AppColors.divider;
              }
              return states.contains(WidgetState.selected)
                  ? AppColors.surface
                  : AppColors.textPrimary;
            }),
            dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? AppColors.primary
                  : null;
            }),
            todayForegroundColor: WidgetStateProperty.all(AppColors.primary),
            todayBorder: const BorderSide(color: AppColors.primary),
            yearForegroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? AppColors.surface
                  : AppColors.textPrimary;
            }),
            yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? AppColors.primary
                  : null;
            }),
            cancelButtonStyle: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            confirmButtonStyle: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
            ),
          ),
        ),
        child: child!,
      );
    },
  );
}
