import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_filter_chip.dart';
import '../../../core/widgets/app_inline_error.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../../core/widgets/user_avatar_with_name.dart';
import '../application/admin_labels.dart';
import '../application/admin_providers.dart';
import '../data/admin_support_models.dart';
import 'admin_jobs_page.dart';
import 'widgets/admin_panel_widgets.dart';
import 'widgets/admin_stat_widgets.dart';

/// Secção Clientes (`/admin/clientes` e `/admin/clientes/:id`).
class AdminClientsPage extends StatelessWidget {
  const AdminClientsPage({this.selectedClientId, super.key});

  final String? selectedClientId;

  @override
  Widget build(BuildContext context) {
    final id = selectedClientId;
    return AdminSplitView(
      list: AdminClientsList(selectedClientId: id),
      detailKey: id,
      detailBuilder: id == null
          ? null
          : (overlay) => AdminClientDetailPanel(
              key: ValueKey(id),
              clientId: id,
              onClose: overlay ? () => context.go('/admin/clientes') : null,
            ),
      emptyDetail: const AppEmptyState(
        icon: Icons.person_search_outlined,
        title: 'Escolhe um cliente',
        message:
            'A ficha abre aqui, com os pedidos, as avaliações e os '
            'reportes.',
      ),
    );
  }
}

class AdminClientsList extends ConsumerStatefulWidget {
  const AdminClientsList({this.selectedClientId, super.key});

  final String? selectedClientId;

  @override
  ConsumerState<AdminClientsList> createState() => _AdminClientsListState();
}

class _AdminClientsListState extends ConsumerState<AdminClientsList> {
  late final TextEditingController _search;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(
      text: ref.read(adminClientsFilterProvider).search,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _set(AdminClientsFilter filter) =>
      ref.read(adminClientsFilterProvider.notifier).update(filter);

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _set(ref.read(adminClientsFilterProvider).copyWith(search: value.trim()));
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(adminClientsFilterProvider);
    final clientsAsync = ref.watch(adminClientsProvider(filter));
    final textTheme = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminClientsProvider(filter).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          AppSearchField(
            controller: _search,
            hintText: 'Nome, email ou telefone',
            onChanged: _onSearch,
            onClear: () {
              _search.clear();
              _onSearch('');
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final (value, label) in const [
                (null, 'Todas'),
                ('active', 'Ativas'),
                ('deleted', 'Eliminadas'),
              ])
                AppFilterChip(
                  label: label,
                  selected: filter.state == value,
                  onPressed: () => _set(filter.copyWith(state: () => value)),
                ),
              AppFilterChip(
                label: 'Com reportes',
                leadingIcon: Icons.flag_outlined,
                selected: filter.withReports,
                onPressed: () =>
                    _set(filter.copyWith(withReports: !filter.withReports)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          clientsAsync.when(
            loading: () => const AdminLoadingBlocks(count: 5, height: 72),
            error: (error, _) => AppInlineError(
              message: friendlyError(error),
              onRetry: () => ref.invalidate(adminClientsProvider(filter)),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.person_search_outlined,
                  title: 'Nenhum cliente',
                  message: 'Nenhum cliente corresponde a esta pesquisa.',
                );
              }
              final total = rows.first.totalCount;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '$total clientes',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (final (i, row) in rows.indexed) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: i < 6 ? i : 6,
                      child: AdminClientRowCard(
                        row: row,
                        selected: row.clientId == widget.selectedClientId,
                        onPressed: () =>
                            context.go('/admin/clientes/${row.clientId}'),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  AdminPager(
                    page: filter.page,
                    pages: (total / adminClientsPageSize).ceil(),
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

class AdminClientRowCard extends StatelessWidget {
  const AdminClientRowCard({
    required this.row,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final AdminClientRow row;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (row.email != null) row.email!,
      '${row.jobsTotal} pedidos',
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
              name: row.fullName ?? '',
              avatarUrl: row.avatarUrl,
              fallbackLabel: 'Sem nome',
              subtitle: details,
            ),
          ),
          if (row.reportsCount > 0) ...[
            const SizedBox(width: AppSpacing.xs),
            Tooltip(
              message: '${row.reportsCount} reportes',
              child: const Icon(
                Icons.flag_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (row.deletedAt != null) ...[
            const SizedBox(width: AppSpacing.xs),
            const AppStatusBadge(
              label: 'Eliminada',
              statusColor: AppStatusColor.neutral,
              dense: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// Ficha de um cliente. Abrir fica registado (admin_get_client).
class AdminClientDetailPanel extends ConsumerWidget {
  const AdminClientDetailPanel({
    required this.clientId,
    this.onClose,
    super.key,
  });

  final String clientId;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = ref.watch(adminClientDetailProvider(clientId));
    return clientAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: AdminLoadingBlocks(),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppInlineError(
          message: friendlyError(error),
          onRetry: () => ref.invalidate(adminClientDetailProvider(clientId)),
        ),
      ),
      data: (client) => RefreshIndicator(
        onRefresh: () =>
            ref.refresh(adminClientDetailProvider(clientId).future),
        child: AdminClientDetailView(
          client: client,
          onClose: onClose,
          onOpenJob: (id) => context.go('/admin/pedidos/$id'),
          phone: AdminRevealPhone(
            personId: client.clientId,
            maskedPhone: client.hasPhone ? client.phoneMasked : null,
          ),
        ),
      ),
    );
  }
}

/// Vista pura da ficha do cliente. [phone] é o widget de "Mostrar
/// contacto" (injetado para os testes não precisarem da BD).
class AdminClientDetailView extends StatelessWidget {
  const AdminClientDetailView({
    required this.client,
    required this.onOpenJob,
    required this.phone,
    this.onClose,
    super.key,
  });

  final AdminClientDetail client;
  final ValueChanged<String> onOpenJob;
  final Widget phone;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = client;
    final textTheme = Theme.of(context).textTheme;
    final sections = <Widget>[
      AdminPanelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (onClose != null)
                  IconButton(
                    tooltip: 'Voltar à lista',
                    onPressed: onClose,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                Expanded(
                  child: UserAvatarWithName(
                    name: c.fullName ?? '',
                    avatarUrl: c.avatarUrl,
                    radius: 26,
                    fallbackLabel: 'Sem nome',
                    nameStyle: textTheme.titleLarge?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    subtitle: 'Cliente · ${adminShortId(c.clientId)}',
                  ),
                ),
                AppStatusBadge(
                  label: c.deletedAt != null ? 'Conta eliminada' : 'Ativa',
                  statusColor: c.deletedAt != null
                      ? AppStatusColor.neutral
                      : AppStatusColor.success,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            AdminInfoRow(
              label: 'Email',
              value: [
                c.email ?? '—',
                if (c.email != null && !c.emailConfirmed) '(por confirmar)',
              ].join(' '),
              trailing: c.email == null
                  ? null
                  : AdminCopyButton(value: c.email!, tooltip: 'Copiar email'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      'Telefone',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(child: phone),
                ],
              ),
            ),
            AdminInfoRow(
              label: 'Conta criada',
              value: adminDateLabel(c.createdAt),
            ),
            AdminInfoRow(
              label: 'Última entrada',
              value: adminRelativeDateLabel(c.lastSignInAt),
            ),
            if (c.deletedAt != null)
              AdminInfoRow(
                label: 'Eliminada a',
                value: adminDateLabel(c.deletedAt),
              ),
            AdminInfoRow(
              label: 'Aparelhos com push',
              value: c.pushDevices == 0 ? 'Nenhum' : '${c.pushDevices}',
            ),
          ],
        ),
      ),
      AdminPanelCard(
        title: 'Pedidos (${c.jobs.length})',
        child: c.jobs.isEmpty
            ? Text(
                'Ainda não fez pedidos.',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              )
            : Column(
                children: [
                  for (final (i, j) in c.jobs.indexed) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.xs),
                    AdminListTileCard(
                      onPressed: () => onOpenJob(j.jobId),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  j.serviceName ?? 'Pedido',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  [
                                    adminShortId(j.jobId),
                                    adminDateLabel(j.createdAt),
                                    if (j.workerName != null) j.workerName!,
                                    if (j.locationArea != null) j.locationArea!,
                                  ].join(' · '),
                                  style: textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (j.hasReport)
                            const Padding(
                              padding: EdgeInsets.only(right: AppSpacing.xs),
                              child: Icon(
                                Icons.flag_rounded,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          AdminJobStatusBadge(
                            status: j.status,
                            statusValue: j.statusValue,
                            proposalCount: j.proposalCount,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
      ),
      if (c.reports.isNotEmpty)
        AdminPanelCard(
          title: 'Reportes (${c.reports.length})',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in c.reports)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    '${adminDateTimeLabel(r.createdAt)} · '
                    '${r.byClient ? 'feito por este cliente' : 'num pedido dele'}: '
                    '${r.description}',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      _RatingsCard(title: 'Avaliações que deu', items: c.ratingsGiven),
      _RatingsCard(title: 'Avaliações que recebeu', items: c.ratingsReceived),
      if (c.adminHistory.isNotEmpty)
        AdminPanelCard(
          title: 'Histórico do suporte',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final h in c.adminHistory)
                Text(
                  '${adminDateTimeLabel(h.createdAt)} · '
                  '${adminHistoryActionLabel(h.action)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        for (final (i, section) in sections.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          AppStaggeredEntrance(index: i < 6 ? i : 6, child: section),
        ],
      ],
    );
  }
}

class _RatingsCard extends StatelessWidget {
  const _RatingsCard({required this.title, required this.items});

  final String title;
  final List<AdminRatingItem> items;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AdminPanelCard(
      title: '$title (${items.length})',
      child: items.isEmpty
          ? Text(
              'Nenhuma.',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Text(
                      '${'★' * r.stars} · ${r.personName ?? 'Sem nome'} · '
                      '${adminDateLabel(r.createdAt)}'
                      '${r.comment == null ? '' : '\n"${r.comment}"'}',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
