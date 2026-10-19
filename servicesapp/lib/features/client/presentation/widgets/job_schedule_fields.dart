import 'package:flutter/material.dart';

import '../../../../core/constants/enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_labels.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../application/job_request_form.dart';

// Campos de agendamento de um pedido (design U3), partilhados pelo passo 2
// do wizard (client_create_job_schedule_screen.dart) e por "Editar pedido"
// (client_edit_job_screen.dart).

/// Texto de cada [DateMode] nos três botões de escolha.
String _dateModeLabel(DateMode mode) => switch (mode) {
      DateMode.fixed => 'Data fixa',
      DateMode.flexible => 'Flexível',
      DateMode.availability => 'Disponibilidade',
    };

/// "Quando precisas do serviço?": três botões (data fixa, flexível,
/// disponibilidade em texto livre) e, por baixo, o campo do modo escolhido.
///
/// Não guarda estado: o ecrã decide o modo, a data e o texto.
class JobScheduleFields extends StatelessWidget {
  const JobScheduleFields({
    super.key,
    required this.dateMode,
    required this.onDateModeChanged,
    required this.date,
    required this.onPickDate,
    required this.availabilityController,
    this.title = 'Quando precisas do serviço?',
    this.missingDateHint,
  });

  final DateMode dateMode;
  final ValueChanged<DateMode> onDateModeChanged;
  final DateTime? date;
  final VoidCallback onPickDate;
  final TextEditingController availabilityController;
  final String title;

  /// Texto por baixo do campo de data enquanto não há data (ex.: a data
  /// antiga já passou em "Editar pedido").
  final String? missingDateHint;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            for (final mode in DateMode.values) ...[
              if (mode != DateMode.values.first)
                const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _ScheduleChoiceButton(
                  label: _dateModeLabel(mode),
                  selected: dateMode == mode,
                  onPressed: () => onDateModeChanged(mode),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AppFadeThroughSwitcher(
          switchKey: dateMode,
          duration: AppMotionDuration.fast,
          child: switch (dateMode) {
            DateMode.fixed => Column(
                key: const ValueKey('schedule_fixed'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  JobDateField(date: date, onPressed: onPickDate),
                  if (date == null && missingDateHint != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      missingDateHint!,
                      style: textTheme.labelMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            DateMode.flexible => Text(
                'Combinas a data com o jardineiro.',
                key: const ValueKey('schedule_flexible'),
                style: textTheme.labelMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            DateMode.availability => AvailabilityTextField(
                key: const ValueKey('schedule_availability'),
                controller: availabilityController,
              ),
          },
        ),
      ],
    );
  }
}

class _ScheduleChoiceButton extends StatelessWidget {
  const _ScheduleChoiceButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.primaryContainer : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.input),
          child: Container(
            alignment: Alignment.center,
            constraints: const BoxConstraints(
              minHeight: AppSizes.scheduleChoiceHeight,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.divider,
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: textTheme.labelMedium?.copyWith(
                color: selected ? AppColors.primary : AppColors.textPrimary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Campo de data (abre o seletor no toque): "Data" no rebordo e o dia
/// escrito como "Sábado, 25/10".
class JobDateField extends StatelessWidget {
  const JobDateField({
    required this.date,
    required this.onPressed,
    super.key,
  });

  final DateTime? date;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final value = date;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.input),
      borderSide: const BorderSide(color: AppColors.divider),
    );

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(minHeight: AppSizes.dateFieldMinHeight),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Data',
            floatingLabelBehavior: FloatingLabelBehavior.always,
            labelStyle:
                textTheme.labelLarge?.copyWith(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.s18,
            ),
            suffixIcon: const Icon(
              Icons.calendar_month_outlined,
              color: AppColors.textSecondary,
            ),
            enabledBorder: border,
            border: border,
          ),
          child: Text(
            value == null ? 'Escolher data' : weekdayDateLabel(value),
            style: textTheme.bodyMedium?.copyWith(
              color: value == null
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Texto livre da disponibilidade (`DateMode.availability`), com a dica e
/// o contador por baixo.
class AvailabilityTextField extends StatelessWidget {
  const AvailabilityTextField({required this.controller, super.key});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.input),
      borderSide: const BorderSide(color: AppColors.primary),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          minLines: 2,
          maxLines: 4,
          maxLength: availabilityTextMaxLength,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: availabilityTextHint,
            hintStyle:
                textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            counterText: '',
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.all(AppSpacing.md),
            enabledBorder: border,
            focusedBorder: border,
            border: border,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => Row(
            children: [
              Expanded(
                child: Text(
                  'Diz por palavras tuas quando dá jeito',
                  style: textTheme.labelMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              Text(
                '${value.text.length}/$availabilityTextMaxLength',
                style: textTheme.labelMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
