import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_filter_chip.dart';
import '../../../core/widgets/app_inline_error.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../../core/widgets/app_toast.dart';
import '../application/admin_labels.dart';
import '../application/admin_providers.dart';
import '../data/admin_resolve_models.dart';
import 'widgets/admin_action_dialogs.dart';
import 'widgets/admin_panel_widgets.dart';
import 'widgets/admin_stat_widgets.dart';

/// Denúncias e reportes (`/admin/denuncias`). Os reportes de problema da
/// app chegam aqui; um reporte com fundamento abre um caso (o prazo passa
/// a ser o do caso), um sem fundamento dispensa-se com nota. As denúncias
/// por email entram como caso na Caixa de suporte.
class AdminReportsPage extends ConsumerStatefulWidget {
  const AdminReportsPage({super.key});

  @override
  ConsumerState<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends ConsumerState<AdminReportsPage> {
  String? _status;
  int _page = 0;

  AdminReportsQuery get _query => (status: _status, page: _page);

  Future<void> _openCase(AdminReportRow report) async {
    if (report.caseId != null) {
      context.go('/admin/suporte/${report.caseId}');
      return;
    }
    final id = await showAdminCreateCaseDialog(
      context,
      ref,
      reportId: report.reportId,
      initialKind: AdminCaseKind.report,
      initialSummary: report.description,
    );
    if (id == null || !mounted) return;
    context.go('/admin/suporte/$id');
    AppToast.of(context).show('Caso aberto a partir do reporte.');
    ref.invalidate(adminReportsProvider);
    ref.invalidate(adminCasesProvider);
  }

  Future<void> _dismiss(AdminReportRow report) async {
    final done = await showAdminActionDialog(
      context,
      icon: Icons.do_not_disturb_on_outlined,
      title: 'Dispensar reporte',
      consequence:
          'O reporte fica fechado sem caso. Ninguém é avisado na app; se a '
          'pessoa escrever, responde por email com a nota.',
      confirmLabel: 'Dispensar',
      askReason: false,
      noteLabel: 'Porquê (fica no registo)',
      onSubmit: (input) => ref
          .read(adminRepositoryProvider)
          .setReportStatus(
            report.reportId,
            status: 'dismissed',
            note: input.note,
          ),
    );
    if (!done || !mounted) return;
    AppToast.of(context).show('Reporte dispensado.');
    ref.invalidate(adminReportsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(adminReportsProvider(_query));
    final textTheme = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminReportsProvider(_query).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          Text(
            'Denúncias e reportes',
            style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Reportes de problema feitos na app. Denúncias por email: abre um '
            'caso do tipo Denúncia na Caixa de suporte.',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final (value, label) in const [
                (null, 'Por tratar'),
                ('resolved', 'Resolvidos'),
                ('dismissed', 'Dispensados'),
                ('all', 'Todos'),
              ])
                AppFilterChip(
                  label: label,
                  selected: _status == value,
                  onPressed: () => setState(() {
                    _status = value;
                    _page = 0;
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          reportsAsync.when(
            loading: () => const AdminLoadingBlocks(count: 4, height: 110),
            error: (error, _) => AppInlineError(
              message: friendlyError(error),
              onRetry: () => ref.invalidate(adminReportsProvider(_query)),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.flag_outlined,
                  title: 'Nenhum reporte',
                  message: 'Nenhum reporte com este filtro.',
                );
              }
              final total = rows.first.totalCount;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, row) in rows.indexed) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: i < 6 ? i : 6,
                      child: AdminReportCard(
                        report: row,
                        onOpenJob: () =>
                            context.go('/admin/pedidos/${row.jobId}'),
                        onOpenCase: () => _openCase(row),
                        onDismiss: row.closed || row.caseId != null
                            ? null
                            : () => _dismiss(row),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  AdminPager(
                    page: _page,
                    pages: (total / adminReportsPageSize).ceil(),
                    onPage: (p) => setState(() => _page = p),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class AdminReportCard extends StatelessWidget {
  const AdminReportCard({
    required this.report,
    required this.onOpenJob,
    required this.onOpenCase,
    required this.onDismiss,
    super.key,
  });

  final AdminReportRow report;
  final VoidCallback onOpenJob;
  final VoidCallback onOpenCase;

  /// `null` quando já não se pode dispensar (fechado ou com caso).
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (statusLabel, statusColor) = adminReportStatus(report.status);
    return AdminPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${report.serviceName ?? 'Pedido'} · '
                  '${adminShortId(report.jobId)}',
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              AppStatusBadge(
                label: statusLabel,
                statusColor: statusColor,
                dense: true,
              ),
              const SizedBox(width: AppSpacing.xs),
              AdminDeadlineBadge(dueAt: report.dueAt, closed: report.closed),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            report.description,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            [
              '${report.reporterIsClient ? 'Cliente' : 'Jardineiro'}: '
                  '${report.reporterName ?? 'sem nome'}',
              adminDateTimeLabel(report.createdAt),
              if (report.caseNumber != null) 'caso #${report.caseNumber}',
            ].join(' · '),
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              TextButton.icon(
                onPressed: onOpenJob,
                icon: const Icon(Icons.assignment_outlined, size: 18),
                label: const Text('Ver pedido'),
              ),
              TextButton.icon(
                onPressed: onOpenCase,
                icon: const Icon(Icons.support_agent_rounded, size: 18),
                label: Text(report.caseId == null ? 'Abrir caso' : 'Ver caso'),
              ),
              if (onDismiss != null)
                TextButton.icon(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.do_not_disturb_on_outlined, size: 18),
                  label: const Text('Dispensar'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
