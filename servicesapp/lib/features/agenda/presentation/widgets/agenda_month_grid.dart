import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import 'agenda_entry_card.dart';
import 'agenda_legend.dart';

/// Grelha de um mês para saltar para um dia (folha "Tocar na data" do Hoje).
/// Cada dia mostra até 3 pontos com as cores das entradas. A vista Mês é
/// outra (`AgendaMonthView`); isto é só o seletor.
class AgendaMonthGrid extends StatelessWidget {
  const AgendaMonthGrid({
    required this.month,
    required this.monthLabel,
    required this.selectedDay,
    required this.today,
    required this.dotsByDay,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onDaySelected,
    super.key,
  });

  /// Qualquer dia do mês mostrado.
  final DateTime month;

  /// "Outubro 2026".
  final String monthLabel;
  final DateTime selectedDay;
  final DateTime today;

  /// Dia do mês → tipos das entradas (sem repetir, pela ordem a mostrar).
  final Map<int, List<AgendaCardKind>> dotsByDay;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onDaySelected;

  static const _weekdayInitials = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];
  static const double _cellHeight = 48;
  static const double _dayCircle = 34;
  static const double _dot = 5;
  static const int _maxDots = 3;

  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final first = DateTime(month.year, month.month);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    // Semana a começar à segunda.
    final leading = first.weekday - 1;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();

    Widget dayCell(int day) {
      final date = DateTime(month.year, month.month, day);
      final selected = _same(date, selectedDay);
      final isToday = _same(date, today);
      final dots = (dotsByDay[day] ?? const []).take(_maxDots).toList();
      return Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: () => onDaySelected(date),
          customBorder: const CircleBorder(),
          child: SizedBox(
            height: _cellHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: _dayCircle,
                  height: _dayCircle,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : null,
                    shape: BoxShape.circle,
                    border: isToday && !selected
                        ? Border.all(color: AppColors.primary, width: 1.5)
                        : null,
                  ),
                  child: Text(
                    '$day',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: selected || isToday
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: selected
                          ? AppColors.surface
                          : isToday
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: _dot,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < dots.length; i++) ...[
                        if (i > 0) const SizedBox(width: 2),
                        AgendaKindDot(kind: dots[i], size: _dot),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onPreviousMonth,
              tooltip: 'Mês anterior',
              icon: const Icon(
                Icons.chevron_left_rounded,
                color: AppColors.textSecondary,
              ),
            ),
            Expanded(
              child: Text(
                monthLabel,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              onPressed: onNextMonth,
              tooltip: 'Mês seguinte',
              icon: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            for (final w in _weekdayInitials)
              Expanded(
                child: Text(
                  w,
                  textAlign: TextAlign.center,
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: () {
                    final day = r * 7 + c - leading + 1;
                    if (day < 1 || day > daysInMonth) {
                      return const SizedBox(height: _cellHeight);
                    }
                    return dayCell(day);
                  }(),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.sm),
        const Divider(height: 1, color: AppColors.divider),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          alignment: WrapAlignment.center,
          children: [
            for (final (kind, label) in const [
              (AgendaCardKind.app, 'App'),
              (AgendaCardKind.helper, 'Ajudante'),
              (AgendaCardKind.external, 'Fora da app'),
              (AgendaCardKind.block, 'Indisponível'),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AgendaKindDot(kind: kind, size: AppSizes.statusDot + 2),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    label,
                    style: textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
