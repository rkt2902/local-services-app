import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../data/agenda_entry_model.dart';
import '../agenda_day_view_data.dart';
import '../agenda_week_view_data.dart';
import 'agenda_decorations.dart';
import 'agenda_entry_card.dart';
import 'agenda_overlap.dart';

/// Peças comuns à faixa da Semana e à grelha do Mês: a célula de um dia, os
/// pontos e a lista de um dia.

/// Célula de um dia. Hoje com contorno verde; escolhido cheio a verde;
/// indisponível o dia todo riscado; triângulo âmbar quando há horas que se
/// cruzam.
class AgendaDayCell extends StatelessWidget {
  const AgendaDayCell({
    required this.day,
    required this.selected,
    required this.onTap,
    required this.height,
    this.onDoubleTap,
    this.showWeekday = false,
    this.filled = true,
    this.muted = false,
    this.dotsOnStripes = true,
    super.key,
  });

  final AgendaWeekDayViewData day;
  final bool selected;
  final VoidCallback onTap;

  /// Mês: duplo toque abre o Hoje desse dia.
  final VoidCallback? onDoubleTap;
  final double height;

  /// Semana: inicial do dia por cima do número, número maior.
  final bool showWeekday;

  /// Fundo branco (Semana); no Mês a grelha já está num cartão branco.
  final bool filled;

  /// Dia de outro mês na grelha: número a cinzento claro.
  final bool muted;

  /// No Mês, o dia riscado não leva pontos.
  final bool dotsOnStripes;

  static const double _border = 2;
  static const double _warningBadge = 18;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.input);
    final striped = day.unavailable && !selected;
    final showDots = !striped || dotsOnStripes;

    final number = (showWeekday ? textTheme.titleLarge : textTheme.bodyLarge)
        ?.copyWith(
          fontWeight: muted ? FontWeight.w600 : FontWeight.w800,
          height: 1.15,
          color: selected
              ? AppColors.surface
              : muted
              ? AppColors.agendaDashed
              : striped
              ? AppColors.textSecondary
              : AppColors.textPrimary,
        );

    // Letra grande ou ecrã estreito: encolhe em vez de partir.
    final inner = Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showWeekday)
              Text(
                day.weekdayLetter,
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppColors.primaryContainer
                      : AppColors.textSecondary,
                ),
              ),
            Text(day.dayNumber, style: number),
            SizedBox(height: showWeekday ? AppSpacing.xxs : 2),
            SizedBox(
              height: AppSpacing.s10,
              child: showDots
                  ? AgendaDayDots(kinds: day.dots, onPrimary: selected)
                  : null,
            ),
          ],
        ),
      ),
    );

    final Widget cell = striped
        ? AgendaStripes(
            radius: AppRadius.input,
            child: SizedBox(height: height, child: inner),
          )
        : AnimatedContainer(
            duration: AppMotionDuration.fast,
            height: height,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary
                  : filled
                  ? AppColors.surface
                  : Colors.transparent,
              borderRadius: radius,
              border: Border.all(
                color: day.isToday || selected
                    ? AppColors.primary
                    : Colors.transparent,
                width: _border,
              ),
            ),
            child: inner,
          );

    return Semantics(
      button: true,
      selected: selected,
      label: [
        if (day.isToday) 'Hoje',
        if (day.unavailable) 'indisponível',
        if (day.hasOverlap) 'trabalhos que coincidem',
        if (day.dots.isNotEmpty) '${day.dots.length} na agenda',
      ].join(', '),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              onDoubleTap: onDoubleTap,
              borderRadius: radius,
              child: cell,
            ),
          ),
          if (day.hasOverlap)
            Positioned(
              top: -AppSpacing.xxs,
              right: -AppSpacing.xxs,
              child: IgnorePointer(
                child: Container(
                  width: _warningBadge,
                  height: _warningBadge,
                  decoration: BoxDecoration(
                    color: AppStatusColor.waiting.background,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 1.5),
                  ),
                  child: Icon(
                    Icons.warning_rounded,
                    size: AppSpacing.sm,
                    color: AppStatusColor.waiting.foreground,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Até 3 pontos pela ordem da hora e "+N" a partir do 4.º.
class AgendaDayDots extends StatelessWidget {
  const AgendaDayDots({required this.kinds, this.onPrimary = false, super.key});

  final List<AgendaCardKind> kinds;

  /// Sobre o verde do dia escolhido.
  final bool onPrimary;

  static const int _max = 3;

  @override
  Widget build(BuildContext context) {
    final shown = kinds.take(_max).toList();
    final extra = kinds.length - shown.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          AgendaDayDot(kind: shown[i], onPrimary: onPrimary),
        ],
        if (extra > 0) ...[
          const SizedBox(width: 2),
          Text(
            '+$extra',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1,
              color: onPrimary ? AppColors.surface : AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Ponto de um dia (legenda da Semana e do Mês): app cheio, ajudante verde
/// claro, fora da app só contorno, proposta tracejada, indisponível
/// cinzento cheio. No dia escolhido ganham contorno branco para se lerem
/// sobre o verde.
class AgendaDayDot extends StatelessWidget {
  const AgendaDayDot({required this.kind, this.onPrimary = false, super.key});

  final AgendaCardKind kind;
  final bool onPrimary;

  static const double _size = 8;

  @override
  Widget build(BuildContext context) {
    if (kind == AgendaCardKind.proposal) {
      return SizedBox.square(
        dimension: _size,
        child: AgendaDashedBorder(
          radius: _size / 2,
          color: onPrimary ? AppColors.surface : AppColors.textSecondary,
          strokeWidth: 1.5,
          child: const SizedBox.expand(),
        ),
      );
    }
    final (Color fill, Color? ring) = switch (kind) {
      AgendaCardKind.app => (AppColors.primary, null),
      AgendaCardKind.helper => (AppColors.agendaHelperBar, null),
      AgendaCardKind.external => (AppColors.surface, AppColors.textMuted),
      AgendaCardKind.block => (AppColors.agendaDashed, null),
      AgendaCardKind.proposal => (Colors.transparent, null),
    };
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: onPrimary
            ? Border.all(color: AppColors.surface, width: 1.5)
            : ring == null
            ? null
            : Border.all(color: ring, width: 1.5),
      ),
    );
  }
}

/// As entradas de um dia, em linhas da Semana; as que coincidem empilhadas
/// com a faixa âmbar.
class AgendaDayItemsList extends StatelessWidget {
  const AgendaDayItemsList({
    required this.items,
    required this.onOpenEntry,
    required this.onResolveOverlap,
    super.key,
  });

  final List<AgendaWeekItem> items;
  final ValueChanged<AgendaDayEntryViewData> onOpenEntry;

  /// Toque no título de um grupo: "Mudar a hora" de um deles.
  final ValueChanged<List<AgendaEntry>> onResolveOverlap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: item.group != null
                ? AgendaOverlapStack(
                    label: item.group!.label,
                    onLabelTap: () => onResolveOverlap([
                      for (final e in item.group!.entries) e.source,
                    ]),
                    children: [for (final e in item.group!.entries) _row(e)],
                  )
                : _row(item.entry!),
          ),
      ],
    );
  }

  Widget _row(AgendaDayEntryViewData e) {
    return AgendaWeekEntryRow(
      kind: e.kind,
      title: e.title,
      startLabel: e.startLabel,
      endLabel: e.endLabel,
      subtitle: e.subtitle,
      repeats: e.repeats,
      timeToArrange: e.timeToArrange,
      dayIndex: e.dayIndex,
      dayCount: e.dayCount,
      pill: e.pill,
      done: e.done,
      onTap: () => onOpenEntry(e),
    );
  }
}
