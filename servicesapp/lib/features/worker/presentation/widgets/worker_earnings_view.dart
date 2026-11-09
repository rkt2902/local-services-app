import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/utils/price_labels.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../../../core/widgets/app_tab_header.dart';
import '../../application/worker_earnings.dart';
import '../../data/worker_earnings_model.dart';

/// Painel de ganhos do jardineiro: um mês de cada vez, com as barras dos
/// últimos 6 meses e a lista dos trabalhos. Sem Riverpod nem navegação:
/// recebe os meses já agrupados ([groupEarningsByMonth]).
class WorkerEarningsView extends StatefulWidget {
  const WorkerEarningsView({
    super.key,
    required this.locked,
    required this.monthsAsync,
    required this.onBack,
    required this.onOpenPlans,
    required this.onRetry,
    required this.onRefresh,
  });

  /// Plano Grátis: mostra só o convite para o Pro.
  final bool locked;

  /// Os 12 meses até ao atual, do mais antigo para o mais recente.
  final AsyncValue<List<WorkerEarningsMonth>> monthsAsync;
  final VoidCallback onBack;
  final VoidCallback onOpenPlans;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;

  @override
  State<WorkerEarningsView> createState() => _WorkerEarningsViewState();
}

class _WorkerEarningsViewState extends State<WorkerEarningsView> {
  /// Índice do mês escolhido; `null` = o mais recente.
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBackHeader(
              title: 'Ganhos',
              subtitle: 'O que combinaste receber pelos trabalhos feitos',
              onBack: widget.onBack,
            ),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (widget.locked) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: AppStaggeredEntrance(
            index: 0,
            child: AppEmptyState(
              icon: Icons.insights_outlined,
              title: 'Painel de ganhos no Pro',
              message: 'Com o plano Pro vês quanto fizeste em cada mês, as '
                  'horas registadas e o que ainda está por confirmar.',
              actionLabel: 'Ver planos',
              onAction: widget.onOpenPlans,
            ),
          ),
        ),
      );
    }

    return widget.monthsAsync.when(
      loading: () => const AppScreenLoadingSkeleton(),
      error: (_, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: AppEmptyState(
            icon: Icons.wifi_off_rounded,
            title: 'Não deu para carregar os ganhos',
            message: 'Verifica a ligação e tenta outra vez.',
            actionLabel: 'Tentar outra vez',
            onAction: widget.onRetry,
            tone: AppStatusColor.cancelled,
          ),
        ),
      ),
      data: (months) {
        if (months.isEmpty) return const SizedBox.shrink();
        final index = (_selected ?? months.length - 1).clamp(0, months.length - 1);
        final month = months[index];
        final chartStart = (index - 5).clamp(0, months.length - 1);
        final chartMonths = months.sublist(chartStart, index + 1);

        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          color: AppColors.primary,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            children: [
              AppStaggeredEntrance(
                index: 0,
                child: _MonthSwitcher(
                  label: earningsMonthLabel(month.month),
                  onPrevious:
                      index > 0 ? () => setState(() => _selected = index - 1) : null,
                  onNext: index < months.length - 1
                      ? () => setState(() => _selected = index + 1)
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppFadeThroughSwitcher(
                switchKey: month.month,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppStaggeredEntrance(
                      index: 1,
                      child: _SummaryCard(month: month),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(
                      index: 2,
                      child: _MonthBars(
                        months: chartMonths,
                        selected: month.month,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (month.entries.isEmpty)
                      AppStaggeredEntrance(
                        index: 3,
                        child: const AppEmptyState(
                          icon: Icons.event_available_outlined,
                          title: 'Sem trabalhos feitos neste mês',
                          message: 'Os trabalhos aparecem aqui quando os '
                              'marcas como feitos.',
                        ),
                      )
                    else
                      for (var i = 0; i < month.entries.length; i++)
                        AppStaggeredEntrance(
                          index: (3 + i).clamp(0, 5),
                          child: _EntryRow(entry: month.entries[i]),
                        ),
                    if (month.hasEstimates) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '≈ Valor estimado pela duração da proposta, porque o '
                        'trabalho não teve "Iniciar".',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onPrevious,
          tooltip: 'Mês anterior',
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppColors.textPrimary),
          ),
        ),
        IconButton(
          onPressed: onNext,
          tooltip: 'Mês seguinte',
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.month});

  final WorkerEarningsMonth month;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final jobs = month.jobCount == 1 ? '1 trabalho' : '${month.jobCount} trabalhos';
    final hours = earningsHoursLabel(month.registeredHours);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total do mês',
            style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${month.hasEstimates ? '≈ ' : ''}${moneyLabel(month.total)}',
            style: textTheme.headlineSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            hours == '—' ? jobs : '$jobs · $hours registadas',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          if (month.awaitingTotal > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: AppStatusColor.waiting.background,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '${moneyLabel(month.awaitingTotal)} por confirmar pelo cliente',
                style: textTheme.labelSmall?.copyWith(
                  color: AppStatusColor.waiting.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Barras simples dos últimos meses; o mês escolhido a verde cheio.
class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.months, required this.selected});

  final List<WorkerEarningsMonth> months;
  final DateTime selected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final maxTotal = months.fold<double>(0, (m, e) => e.total > m ? e.total : m);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final m in months)
            Semantics(
              label: '${earningsMonthLabel(m.month)}: ${moneyLabel(m.total)}',
              excludeSemantics: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: AppMotionDuration.fast,
                    width: AppSizes.earningsBarWidth,
                    height: maxTotal <= 0
                        ? AppSpacing.xxs
                        : (AppSizes.earningsChartHeight * m.total / maxTotal)
                            .clamp(AppSpacing.xxs, AppSizes.earningsChartHeight),
                    decoration: BoxDecoration(
                      color: m.month == selected
                          ? AppColors.primary
                          : AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.input / 2),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    earningsMonthShortLabel(m.month),
                    style: textTheme.labelSmall?.copyWith(
                      color: m.month == selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final WorkerEarningEntry entry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.serviceName,
                  style: textTheme.titleSmall?.copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  earningEntrySubtitle(entry),
                  style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            earningAmountLabel(entry),
            style: textTheme.titleSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
