import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// `showTimePicker()` nativo do Flutter com o tema da app, como
/// [showAppDatePicker] (app_date_picker.dart): sempre em 24h, cores da
/// marca em vez das geradas pela seed e cantos de `AppRadius.card`.
/// [helpText] troca o título do diálogo (ex.: "Duração" na Agenda).
Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String? helpText,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    helpText: helpText,
    builder: (context, child) {
      final base = Theme.of(context);
      final textTheme = base.textTheme;
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: Theme(
          data: base.copyWith(
            colorScheme: base.colorScheme.copyWith(
              primary: AppColors.primary,
              onPrimary: AppColors.surface,
              surface: AppColors.surface,
              onSurface: AppColors.textPrimary,
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              helpTextStyle: textTheme.titleMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
              hourMinuteShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              hourMinuteColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.primaryContainer
                    : AppColors.background,
              ),
              hourMinuteTextColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.primary
                    : AppColors.textPrimary,
              ),
              dialBackgroundColor: AppColors.background,
              dialHandColor: AppColors.primary,
              dialTextColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.surface
                    : AppColors.textPrimary,
              ),
              entryModeIconColor: AppColors.textSecondary,
              cancelButtonStyle: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              confirmButtonStyle: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
            ),
          ),
          child: child!,
        ),
      );
    },
  );
}
