import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_filter_chip.dart';
import '../../../core/widgets/app_inline_error.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../worker/application/worker_providers.dart';
import '../application/admin_labels.dart';
import '../application/admin_providers.dart';
import '../data/admin_support_models.dart';
import 'widgets/admin_job_detail_panel.dart';
import 'widgets/admin_panel_widgets.dart';
import 'widgets/admin_stat_widgets.dart';

/// Rótulo curto do estado nos filtros da lista.
String adminJobStatusFilterLabel(JobStatus status) => switch (status) {
  JobStatus.open => 'Abertos',
  JobStatus.confirmed => 'Confirmados',
  JobStatus.awaitingConfirmation => 'À espera de confirmação',
  JobStatus.completed => 'Concluídos',
  JobStatus.noResponse => 'Expirados',
  JobStatus.cancelled => 'Cancelados',
};

/// Secção Pedidos (`/admin/pedidos` e `/admin/pedidos/:id`): lista com
/// filtros à esquerda e ficha do pedido à direita.
class AdminJobsPage extends StatelessWidget {
  const AdminJobsPage({this.selectedJobId, super.key});

  final String? selectedJobId;

  @override
  Widget build(BuildContext context) {
    final id = selectedJobId;
    return AdminSplitView(
      list: AdminJobsList(selectedJobId: id),
      detailKey: id,
      detailBuilder: id == null
          ? null
          : (overlay) => AdminJobDetailPanel(
              key: ValueKey(id),
              jobId: id,
              onClose: overlay ? () => context.go('/admin/pedidos') : null,
            ),
      emptyDetail: const AppEmptyState(
        icon: Icons.assignment_outlined,
        title: 'Escolhe um pedido',
        message:
            'A ficha abre aqui, com a linha do tempo, as fotos, as '
            'propostas, a equipa e os avisos.',
      ),
    );
  }
}

class AdminJobsList extends ConsumerStatefulWidget {
  const AdminJobsList({this.selectedJobId, super.key});

  final String? selectedJobId;

  @override
  ConsumerState<AdminJobsList> createState() => _AdminJobsListState();
}

class _AdminJobsListState extends ConsumerState<AdminJobsList> {
  late final TextEditingController _area;

  @override
  void initState() {
    super.initState();
    _area = TextEditingController(text: ref.read(adminJobsFilterProvider).area);
  }

  @override
  void dispose() {
    _area.dispose();
    super.dispose();
  }

  void _set(AdminJobsFilter filter) =>
      ref.read(adminJobsFilterProvider.notifier).update(filter);

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(adminJobsFilterProvider);
    final jobsAsync = ref.watch(adminJobsProvider(filter));
    final services = ref.watch(serviceTypesProvider).value ?? const [];
    final textTheme = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminJobsProvider(filter).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppFilterChip(
                label: 'Todos',
                selected: filter.status == null,
                onPressed: () => _set(filter.copyWith(status: () => null)),
              ),
              for (final status in JobStatus.values)
                AppFilterChip(
                  label: adminJobStatusFilterLabel(status),
                  selected: filter.status == status,
                  onPressed: () => _set(filter.copyWith(status: () => status)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppFilterChip(
                label: 'Com reporte',
                leadingIcon: Icons.flag_outlined,
                selected: filter.withReport,
                onPressed: () =>
                    _set(filter.copyWith(withReport: !filter.withReport)),
              ),
              AppFilterChip(
                label: 'Pedido direto',
                leadingIcon: Icons.near_me_outlined,
                selected: filter.directOnly,
                onPressed: () =>
                    _set(filter.copyWith(directOnly: !filter.directOnly)),
              ),
              AppFilterChip(
                label: 'Com ajudantes',
                leadingIcon: Icons.group_add_outlined,
                selected: filter.withHelpers,
                onPressed: () =>
                    _set(filter.copyWith(withHelpers: !filter.withHelpers)),
              ),
              for (final days in const [7, 30])
                AppFilterChip(
                  label: 'Últimos $days dias',
                  selected: filter.lastDays == days,
                  onPressed: () => _set(
                    filter.copyWith(
                      lastDays: () => filter.lastDays == days ? null : days,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: AppSearchField(
                  controller: _area,
                  hintText: 'Zona',
                  onSubmitted: (v) => _set(filter.copyWith(area: v.trim())),
                  onClear: () {
                    _area.clear();
                    _set(filter.copyWith(area: ''));
                  },
                ),
              ),
              if (services.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.input),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: filter.serviceTypeId,
                      hint: const Text('Serviço'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Todos os serviços'),
                        ),
                        for (final s in services)
                          DropdownMenuItem<String?>(
                            value: s.id,
                            child: Text(s.name),
                          ),
                      ],
                      onChanged: (v) =>
                          _set(filter.copyWith(serviceTypeId: () => v)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          jobsAsync.when(
            loading: () => const AdminLoadingBlocks(count: 5, height: 76),
            error: (error, _) => AppInlineError(
              message: friendlyError(error),
              onRetry: () => ref.invalidate(adminJobsProvider(filter)),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Nenhum pedido',
                  message: 'Nenhum pedido corresponde a estes filtros.',
                );
              }
              final total = rows.first.totalCount;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '$total pedidos',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (final (i, row) in rows.indexed) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: i < 6 ? i : 6,
                      child: AdminJobRowCard(
                        row: row,
                        selected: row.jobId == widget.selectedJobId,
                        onPressed: () =>
                            context.go('/admin/pedidos/${row.jobId}'),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  AdminPager(
                    page: filter.page,
                    pages: (total / adminJobsPageSize).ceil(),
                    onPage: (p) => _set(filter.copyWith(page: p)),
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

/// Badge de estado igual ao da app (com o número de propostas quando o
/// pedido está aberto); estados desconhecidos mostram o valor cru.
class AdminJobStatusBadge extends StatelessWidget {
  const AdminJobStatusBadge({
    required this.status,
    required this.statusValue,
    required this.proposalCount,
    this.dense = true,
    super.key,
  });

  final JobStatus? status;
  final String statusValue;
  final int proposalCount;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) {
      return AppStatusBadge(
        label: statusValue,
        statusColor: AppStatusColor.neutral,
        dense: dense,
      );
    }
    return AppStatusBadge.fromPresentation(
      presentation: s.presentation(proposalCount: proposalCount),
      dense: dense,
    );
  }
}

class AdminJobRowCard extends StatelessWidget {
  const AdminJobRowCard({
    required this.row,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final AdminJobRow row;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final people = [
      row.clientName ?? 'Cliente sem nome',
      if (row.workerName != null) row.workerName!,
    ].join(' → ');
    final details = [
      adminShortId(row.jobId),
      if (row.locationArea != null) row.locationArea!,
      adminDateLabel(row.createdAt),
    ].join(' · ');
    return AdminListTileCard(
      selected: selected,
      onPressed: onPressed,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.serviceName ?? 'Pedido',
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  people,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  details,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AdminJobStatusBadge(
                status: row.status,
                statusValue: row.statusValue,
                proposalCount: row.proposalCount,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (row.hasReport)
                    const Tooltip(
                      message: 'Tem reporte',
                      child: Icon(
                        Icons.flag_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  if (row.isDirect)
                    const Tooltip(
                      message: 'Pedido direto',
                      child: Icon(
                        Icons.near_me_outlined,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  if (row.hasHelpers)
                    const Tooltip(
                      message: 'Com ajudantes',
                      child: Icon(
                        Icons.group_add_outlined,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
