import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/error_utils.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_filter_chip.dart';
import '../../../../core/widgets/app_inline_error.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/app_status_badge.dart';
import '../../../../core/widgets/user_avatar_with_name.dart';
import '../../application/admin_labels.dart';
import '../../application/admin_providers.dart';
import '../../data/admin_models.dart';
import '../admin_worker_detail_screen.dart';
import 'admin_panel_widgets.dart';
import 'admin_stat_widgets.dart';

/// Secção Jardineiros (`/admin/workers` e `/admin/workers/:id`): lista à
/// esquerda e ficha à direita.
class AdminWorkersPage extends StatelessWidget {
  const AdminWorkersPage({this.selectedWorkerId, super.key});

  final String? selectedWorkerId;

  @override
  Widget build(BuildContext context) {
    final id = selectedWorkerId;
    return AdminSplitView(
      list: AdminWorkersTab(selectedWorkerId: id),
      detailKey: id,
      detailBuilder: id == null
          ? null
          : (overlay) => AdminWorkerDetailPanel(
              key: ValueKey(id),
              workerId: id,
              onClose: overlay ? () => context.go('/admin/workers') : null,
            ),
      emptyDetail: const AppEmptyState(
        icon: Icons.yard_outlined,
        title: 'Escolhe um jardineiro',
        message: 'A ficha abre aqui, com os números de 6 meses e o plano.',
      ),
    );
  }
}

class AdminWorkersTab extends ConsumerStatefulWidget {
  const AdminWorkersTab({this.selectedWorkerId, super.key});

  final String? selectedWorkerId;

  @override
  ConsumerState<AdminWorkersTab> createState() => _AdminWorkersTabState();
}

class _AdminWorkersTabState extends ConsumerState<AdminWorkersTab> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';
  WorkerPlanTier? _tier;
  int _page = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _search = value.trim();
        _page = 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = (search: _search, tier: _tier, page: _page);
    final workersAsync = ref.watch(adminWorkersProvider(query));

    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminWorkersProvider(query).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          AppSearchField(
            controller: _searchController,
            hintText: 'Nome, telefone ou zona',
            onChanged: _onSearchChanged,
            onClear: () {
              _searchController.clear();
              _onSearchChanged('');
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppFilterChip(
                label: 'Todos',
                selected: _tier == null,
                onPressed: () => setState(() {
                  _tier = null;
                  _page = 0;
                }),
              ),
              for (final tier in WorkerPlanTier.values)
                AppFilterChip(
                  label: tier.label,
                  selected: _tier == tier,
                  onPressed: () => setState(() {
                    _tier = tier;
                    _page = 0;
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          workersAsync.when(
            loading: () => const AdminLoadingBlocks(count: 4, height: 72),
            error: (error, _) => AppInlineError(
              message: friendlyError(error),
              onRetry: () => ref.invalidate(adminWorkersProvider(query)),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.person_search_outlined,
                  title: 'Nenhum jardineiro',
                  message: 'Nenhum jardineiro corresponde a esta pesquisa.',
                );
              }
              final total = rows.first.totalCount;
              final pages = (total / adminWorkersPageSize).ceil();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '$total jardineiros',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (final (i, row) in rows.indexed) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: i < 6 ? i : 6,
                      child: _WorkerRowCard(
                        row: row,
                        selected: row.workerId == widget.selectedWorkerId,
                        onPressed: () =>
                            context.go('/admin/workers/${row.workerId}'),
                      ),
                    ),
                  ],
                  if (pages > 1) ...[
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: _page == 0
                              ? null
                              : () => setState(() => _page--),
                          icon: const Icon(Icons.chevron_left_rounded),
                          label: const Text('Anteriores'),
                        ),
                        Text('${_page + 1} de $pages'),
                        TextButton.icon(
                          onPressed: _page >= pages - 1
                              ? null
                              : () => setState(() => _page++),
                          icon: const Icon(Icons.chevron_right_rounded),
                          label: const Text('Seguintes'),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WorkerRowCard extends StatelessWidget {
  const _WorkerRowCard({
    required this.row,
    required this.onPressed,
    this.selected = false,
  });

  final AdminWorkerRow row;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final details = [
      if ((row.locationName ?? '').isNotEmpty) row.locationName!,
      '${row.jobsCompleted} concluídos',
      if (row.ratingCount > 0)
        '${adminRatingLabel(row.avgRating)} ★ (${row.ratingCount})',
      'entrou ${adminRelativeDateLabel(row.lastSignInAt)}',
    ].join(' · ');
    return AdminListTileCard(
      selected: selected,
      onPressed: onPressed,
      child: Row(
        children: [
          Expanded(
            child: UserAvatarWithName(
              name: row.fullName,
              avatarUrl: row.avatarUrl,
              fallbackLabel: 'Sem nome',
              subtitle: details,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          AppStatusBadge(
            label: row.tier.label,
            statusColor: adminTierStatusColor(row.tier),
            dense: true,
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}
