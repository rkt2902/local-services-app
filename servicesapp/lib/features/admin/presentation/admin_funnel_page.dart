import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_filter_chip.dart';
import '../../../core/widgets/app_inline_error.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_toast.dart';
import '../application/admin_labels.dart';
import '../application/admin_providers.dart';
import '../data/admin_growth_models.dart';
import 'widgets/admin_file_share.dart';
import 'widgets/admin_panel_widgets.dart';
import 'widgets/admin_stat_widgets.dart';

/// Períodos do funil: (rótulo, dias). `null` = desde sempre.
const adminFunnelPeriods = <(String, int?)>[
  ('7 dias', 7),
  ('30 dias', 30),
  ('90 dias', 90),
  ('Tudo', null),
];

/// Funil e dados (`/admin/funil`, 0081): até onde chegam clientes, pedidos
/// e jardineiros do período, e exportar as listas em CSV. Contas
/// eliminadas, suspensas e de admin não contam.
class AdminFunnelPage extends ConsumerStatefulWidget {
  const AdminFunnelPage({super.key});

  @override
  ConsumerState<AdminFunnelPage> createState() => _AdminFunnelPageState();
}

class _AdminFunnelPageState extends ConsumerState<AdminFunnelPage> {
  int? _days = 30;
  AdminExportKind? _exporting;

  Future<void> _export(AdminExportKind kind) async {
    setState(() => _exporting = kind);
    final toast = AppToast.of(context);
    try {
      final table = await ref
          .read(adminRepositoryProvider)
          .exportRows(kind, days: _days);
      final name = adminCsvFileName(kind, DateTime.now());
      final shared = await adminShareTextFile(
        name: name,
        mimeType: 'text/csv',
        text: adminCsv(table),
      );
      toast.show(
        shared
            ? '${table.rows.length} linhas exportadas.'
            : 'CSV copiado (${table.rows.length} linhas). Cola num '
                  'ficheiro $name.',
      );
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
    if (mounted) ref.invalidate(adminActionsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final funnelAsync = ref.watch(adminFunnelProvider(_days));
    final textTheme = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminFunnelProvider(_days).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          Text(
            'Funil e dados',
            style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Quem se registou ou pediu no período e até onde chegou. Contas '
            'eliminadas, suspensas e de admin ficam de fora.',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final (label, days) in adminFunnelPeriods)
                AppFilterChip(
                  label: label,
                  selected: _days == days,
                  onPressed: () => setState(() => _days = days),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          funnelAsync.when(
            loading: () => const AdminLoadingBlocks(count: 3, height: 220),
            error: (e, _) => AppInlineError(
              message: friendlyError(e),
              onRetry: () => ref.invalidate(adminFunnelProvider(_days)),
            ),
            data: (funnel) => AppFadeThroughSwitcher(
              switchKey: _days ?? 0,
              child: AdminFunnelView(funnel: funnel),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppStaggeredEntrance(
            index: 4,
            child: AdminExportCard(
              exporting: _exporting,
              periodLabel: adminFunnelPeriods
                  .firstWhere((p) => p.$2 == _days)
                  .$1,
              onExport: _export,
            ),
          ),
        ],
      ),
    );
  }
}

/// Os três funis, sem Riverpod.
class AdminFunnelView extends StatelessWidget {
  const AdminFunnelView({required this.funnel, super.key});

  final AdminFunnel funnel;

  @override
  Widget build(BuildContext context) {
    final f = funnel;
    final hours = f.medianHoursToFirstProposal;
    final cards = [
      AdminFunnelCard(title: 'Clientes', steps: f.clients),
      AdminFunnelCard(
        title: 'Pedidos',
        steps: f.jobs,
        footnote: [
          '${f.jobsOpen} abertos',
          '${f.jobsNoResponse} sem resposta',
          '${f.jobsCancelled} cancelados',
          if (hours != null)
            '1.ª proposta em ${adminHoursLabel(hours)} (mediana)',
        ].join(' · '),
      ),
      AdminFunnelCard(title: 'Profissionais', steps: f.workers),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, card) in cards.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          AppStaggeredEntrance(index: i, child: card),
        ],
      ],
    );
  }
}

class AdminFunnelCard extends StatelessWidget {
  const AdminFunnelCard({
    required this.title,
    required this.steps,
    this.footnote,
    super.key,
  });

  final String title;
  final List<AdminFunnelStep> steps;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final first = steps.isEmpty ? 0 : steps.first.count;
    return AdminPanelCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final step in steps) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    step.label,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${step.count}',
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(
                  width: AppSizes.slotsValueWidth,
                  child: Text(
                    adminFunnelPercent(step.count, first),
                    textAlign: TextAlign.end,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: first <= 0 ? 0 : step.count / first,
                minHeight: AppSizes.progressBarHeight,
                color: AppColors.primary,
                backgroundColor: AppColors.primaryContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (footnote != null)
            Text(
              footnote!,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

class AdminExportCard extends StatelessWidget {
  const AdminExportCard({
    required this.exporting,
    required this.periodLabel,
    required this.onExport,
    super.key,
  });

  /// O que está a exportar agora, ou `null`.
  final AdminExportKind? exporting;
  final String periodLabel;
  final ValueChanged<AdminExportKind> onExport;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AdminPanelCard(
      title: 'Exportar em CSV',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Registos do período ($periodLabel), até 10 000 linhas. Sem '
            'telefones, emails nem moradas. Abre no Excel; cada exportação '
            'fica no Registo.',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final kind in AdminExportKind.values)
                OutlinedButton.icon(
                  onPressed: exporting == null ? () => onExport(kind) : null,
                  icon: exporting == kind
                      ? const SizedBox.square(
                          dimension: AppSizes.inlineSpinner,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.download_rounded,
                          size: AppSizes.inlineIcon,
                        ),
                  label: Text(kind.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
