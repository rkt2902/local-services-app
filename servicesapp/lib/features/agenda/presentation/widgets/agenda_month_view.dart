import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/primary_action_button.dart';
import '../../data/agenda_entry_model.dart';
import '../agenda_day_presenter.dart';
import '../agenda_month_presenter.dart';
import '../agenda_week_presenter.dart';
import '../agenda_week_view_data.dart';
import 'agenda_controls.dart';
import 'agenda_day_cells.dart';
import 'agenda_decorations.dart';
import 'agenda_skeleton.dart';
import 'agenda_view_parts.dart';

/// Agenda · Mês (design M1 a M3): a grelha do mês e, por baixo, a lista do
/// dia escolhido. Só o corpo da tab Agenda, como o Hoje e a Semana. Não lê
/// providers: a integração (`worker_agenda_tab.dart`) passa tudo pronto.
///
/// Toque num dia escolhe-o (num dia de outro mês, muda de mês); duplo toque
/// ou "Ver dia" abre-o no Hoje.
class AgendaMonthView extends StatefulWidget {
  const AgendaMonthView({
    required this.monthKey,
    required this.monthLabel,
    required this.isCurrentMonth,
    required this.showProposals,
    required this.cells,
    required this.selectedDay,
    required this.selected,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onGoToToday,
    required this.onOpenCalendar,
    required this.onRangeChanged,
    required this.onShowProposalsChanged,
    required this.onRefresh,
    required this.onSelectDay,
    required this.onOpenDay,
    required this.onOpenEntry,
    required this.onResolveOverlap,
    this.loading = false,
    this.errorMessage,
    this.offlineLabel,
    this.onRetry,
    this.onAddToAgendaOnDay,
    super.key,
  });

  /// "2026-10": muda = troca de mês (fade de 180 ms).
  final String monthKey;

  /// "Outubro 2026".
  final String monthLabel;

  /// Sem botão "Hoje" no mês atual.
  final bool isCurrentMonth;
  final bool showProposals;

  /// A grelha: existe mesmo a carregar (só faltam os pontos).
  final List<AgendaMonthCellViewData> cells;
  final DateTime selectedDay;

  /// Lista do dia escolhido; nula enquanto não há dados.
  final AgendaWeekSectionViewData? selected;
  final bool loading;
  final String? errorMessage;
  final String? offlineLabel;

  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onGoToToday;
  final VoidCallback onOpenCalendar;
  final ValueChanged<AgendaRange> onRangeChanged;
  final ValueChanged<bool> onShowProposalsChanged;
  final Future<void> Function() onRefresh;
  final VoidCallback? onRetry;

  /// Toque num dia (também dos meses ao lado).
  final ValueChanged<DateTime> onSelectDay;

  /// Duplo toque, "Ver dia" e entradas sem detalhe: abre o Hoje nesse dia.
  final ValueChanged<DateTime> onOpenDay;

  /// Toque num cartão com detalhe (trabalho, proposta).
  final ValueChanged<AgendaEntry> onOpenEntry;
  final ValueChanged<List<AgendaEntry>> onResolveOverlap;

  /// "Adicionar neste dia"; nulo enquanto o formulário não existe.
  final ValueChanged<DateTime>? onAddToAgendaOnDay;

  @override
  State<AgendaMonthView> createState() => _AgendaMonthViewState();
}

class _AgendaMonthViewState extends State<AgendaMonthView> {
  Timer? _skeletonDelay;
  bool _refreshSkeleton = false;

  static const _monthFade = Duration(milliseconds: 180);
  static const _dayFade = Duration(milliseconds: 150);
  static const _refreshSkeletonAfter = Duration(milliseconds: 400);
  static const _swipeVelocity = 250.0;

  @override
  void dispose() {
    _skeletonDelay?.cancel();
    super.dispose();
  }

  /// Puxar para baixo: o esqueleto só aparece se demorar mais de 400 ms.
  Future<void> _refresh() async {
    _skeletonDelay?.cancel();
    _skeletonDelay = Timer(_refreshSkeletonAfter, () {
      if (mounted) setState(() => _refreshSkeleton = true);
    });
    try {
      await widget.onRefresh();
    } finally {
      _skeletonDelay?.cancel();
      if (mounted && _refreshSkeleton) {
        setState(() => _refreshSkeleton = false);
      }
    }
  }

  void _onGridSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < _swipeVelocity) return;
    velocity < 0 ? widget.onNextMonth() : widget.onPreviousMonth();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AgendaViewControls(
          periodLabel: widget.monthLabel,
          range: AgendaRange.month,
          showToday: !widget.isCurrentMonth,
          showProposals: widget.showProposals,
          onPrevious: widget.onPreviousMonth,
          onNext: widget.onNextMonth,
          onOpenCalendar: widget.onOpenCalendar,
          onRangeChanged: widget.onRangeChanged,
          onGoToToday: widget.onGoToToday,
          onShowProposalsChanged: widget.onShowProposalsChanged,
        ),
        Expanded(
          child: AppFadeThroughSwitcher(
            switchKey: widget.monthKey,
            duration: _monthFade,
            child: AgendaRefreshable(
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.xs,
                  AppSpacing.sm,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: _onGridSwipe,
                      child: _MonthGrid(
                        cells: widget.cells,
                        selectedDay: widget.selectedDay,
                        onSelectDay: widget.onSelectDay,
                        onOpenDay: widget.onOpenDay,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (widget.offlineLabel != null && widget.selected != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AgendaOfflineBanner(label: widget.offlineLabel!),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxs,
                      ),
                      child: AppFadeThroughSwitcher(
                        switchKey: agendaDayKey(widget.selectedDay),
                        duration: _dayFade,
                        child: _panel(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _panel() {
    final selected = widget.selected;
    if (_refreshSkeleton || (selected == null && widget.loading)) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgendaEntrySkeleton(compact: true),
          SizedBox(height: AppSpacing.xs),
          AgendaEntrySkeleton(compact: true),
        ],
      );
    }
    if (selected == null) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: AgendaLoadError(
          message: widget.errorMessage,
          onRetry: widget.onRetry,
        ),
      );
    }
    final add = widget.onAddToAgendaOnDay;
    if (selected.isFree) {
      return _FreeDay(
        section: selected,
        onAdd: add == null ? null : () => add(selected.date),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DayHeader(
          section: selected,
          onOpenDay: () => widget.onOpenDay(selected.date),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppStaggeredEntrance(
          index: 0,
          child: AgendaDayItemsList(
            items: selected.items,
            onOpenEntry: (e) => e.canOpen
                ? widget.onOpenEntry(e.source)
                : widget.onOpenDay(selected.date),
            onResolveOverlap: widget.onResolveOverlap,
          ),
        ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.cells,
    required this.selectedDay,
    required this.onSelectDay,
    required this.onOpenDay,
  });

  final List<AgendaMonthCellViewData> cells;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<DateTime> onOpenDay;

  static const double _cellHeight = 48;
  static const double _gap = AppSpacing.xxs;

  @override
  Widget build(BuildContext context) {
    final rows = (cells.length / 7).ceil();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final letter in agendaWeekdayLetters)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xxs,
                    ),
                    child: Text(
                      letter,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          for (var r = 0; r < rows; r++)
            Padding(
              padding: const EdgeInsets.only(top: _gap),
              child: Row(
                children: [
                  for (var c = 0; c < 7; c++) ...[
                    if (c > 0) const SizedBox(width: _gap),
                    Expanded(child: _cell(cells[r * 7 + c])),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(AgendaMonthCellViewData cell) {
    final date = cell.day.date;
    return AgendaDayCell(
      day: cell.day,
      selected: date == selectedDay,
      height: _cellHeight,
      filled: false,
      muted: !cell.inMonth,
      dotsOnStripes: false,
      onTap: () => onSelectDay(date),
      onDoubleTap: () => onOpenDay(date),
    );
  }
}

/// "Quinta, 22 out · 2 trabalhos ⚠ ........ [Ver dia ›]".
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.section, required this.onOpenDay});

  final AgendaWeekSectionViewData section;
  final VoidCallback onOpenDay;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: section.label),
                    if (section.countLabel != null)
                      TextSpan(
                        text: ' · ${section.countLabel}',
                        style: textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              if (section.hasOverlap)
                Icon(
                  Icons.warning_rounded,
                  size: AppSizes.inlineIcon,
                  color: AppStatusColor.waiting.foreground,
                  semanticLabel: 'Trabalhos que coincidem',
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        OutlinedButton.icon(
          style: agendaOutlinedButtonStyle(context).copyWith(
            shape: const WidgetStatePropertyAll(StadiumBorder()),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            ),
          ),
          onPressed: onOpenDay,
          iconAlignment: IconAlignment.end,
          icon: const Icon(
            Icons.chevron_right_rounded,
            size: AppSizes.inlineIcon,
          ),
          label: const Text('Ver dia'),
        ),
      ],
    );
  }
}

/// Dia escolhido sem nada (M3): "Livre" a verde e um só botão.
class _FreeDay extends StatelessWidget {
  const _FreeDay({required this.section, this.onAdd});

  final AgendaWeekSectionViewData section;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: section.label),
              TextSpan(
                text: ' · Livre',
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          style: textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AgendaDashedBorder(
          radius: AppRadius.card,
          color: AppColors.agendaExternalBorder,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Nada marcado neste dia.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (onAdd != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  PrimaryActionButton(
                    label: 'Adicionar neste dia',
                    icon: Icons.add_rounded,
                    onPressed: onAdd,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
