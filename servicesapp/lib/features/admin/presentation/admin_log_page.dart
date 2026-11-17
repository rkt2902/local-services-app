import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_filter_chip.dart';
import '../../../core/widgets/app_inline_error.dart';
import '../../../core/widgets/app_motion.dart';
import '../application/admin_labels.dart';
import '../application/admin_providers.dart';
import '../data/admin_resolve_models.dart';
import 'widgets/admin_panel_widgets.dart';
import 'widgets/admin_stat_widgets.dart';

/// Registo (`/admin/registo`): todas as `admin_actions`, mais recentes
/// primeiro. Por omissão esconde as consultas e deixa só as mudanças.
class AdminLogPage extends ConsumerStatefulWidget {
  const AdminLogPage({super.key});

  @override
  ConsumerState<AdminLogPage> createState() => _AdminLogPageState();
}

/// Ações que se podem escolher no filtro do Registo.
const adminLogActionFilters = [
  'cancel_job',
  'reopen_job',
  'set_job_status',
  'hide_rating',
  'restore_rating',
  'hide_photo',
  'case_create',
  'case_update',
  'report_status',
  'add_note',
  'suspend_user',
  'reactivate_user',
  'schedule_closure',
  'cancel_closure',
  'erase_user',
  'export_user',
  'hide_profile_photo',
  'resend_code',
  'export_csv',
  'send_notice',
  'fleet_card_approved',
  'fleet_card_rejected',
  'fleet_card_revoked',
  'partner_created',
  'partner_updated',
  'partner_deleted',
  'set_worker_plan',
  'reveal_phone',
  'reveal_address',
];

class _AdminLogPageState extends ConsumerState<AdminLogPage> {
  AdminActionsQuery _query = (includeReads: false, action: null, page: 0);

  @override
  Widget build(BuildContext context) {
    final q = _query;
    final actionsAsync = ref.watch(adminActionsProvider(q));
    final textTheme = Theme.of(context).textTheme;
    void set(AdminActionsQuery next) => setState(() => _query = next);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminActionsProvider(q).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          Text(
            'Registo',
            style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Tudo o que o suporte fez: quem, quando, a quê e porquê. Não se '
            'apaga nem se edita.',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // A lista de ações é longa: escolhe-se num menu, não em filtros.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppFilterChip(
                label: 'Mostrar consultas',
                leadingIcon: Icons.visibility_outlined,
                selected: q.includeReads,
                onPressed: () => set((
                  includeReads: !q.includeReads,
                  action: q.action,
                  page: 0,
                )),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSizes.dialogMaxWidth,
                ),
                child: DropdownButtonFormField<String?>(
                  initialValue: q.action,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Ação'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Todas as ações'),
                    ),
                    for (final action in adminLogActionFilters)
                      DropdownMenuItem(
                        value: action,
                        child: Text(adminHistoryActionLabel(action)),
                      ),
                  ],
                  onChanged: (action) => set((
                    includeReads:
                        q.includeReads ||
                        (action != null && adminIsReadAction(action)),
                    action: action,
                    page: 0,
                  )),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          actionsAsync.when(
            loading: () => const AdminLoadingBlocks(count: 5, height: 64),
            error: (error, _) => AppInlineError(
              message: friendlyError(error),
              onRetry: () => ref.invalidate(adminActionsProvider(q)),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.history_rounded,
                  title: 'Registo vazio',
                  message: 'Nenhuma ação com este filtro.',
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
                      child: AdminActionRowCard(row: row),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  AdminPager(
                    page: q.page,
                    pages: (total / adminActionsPageSize).ceil(),
                    onPage: (p) => set((
                      includeReads: q.includeReads,
                      action: q.action,
                      page: p,
                    )),
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

class AdminActionRowCard extends StatelessWidget {
  const AdminActionRowCard({required this.row, super.key});

  final AdminActionRow row;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final why = [
      if (row.reason != null) AdminActionReason.labelOf(row.reason),
      ?row.note,
    ].join(': ');
    return AdminPanelCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  adminHistoryActionLabel(row.action),
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                if (why.isNotEmpty)
                  Text(
                    why,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                Text(
                  [
                    adminDateTimeLabel(row.createdAt),
                    row.adminEmail ?? 'admin',
                    if (row.targetId != null) adminShortId(row.targetId!),
                  ].join(' · '),
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (row.targetId != null)
            AdminCopyButton(value: row.targetId!, tooltip: 'Copiar id do alvo'),
        ],
      ),
    );
  }
}
