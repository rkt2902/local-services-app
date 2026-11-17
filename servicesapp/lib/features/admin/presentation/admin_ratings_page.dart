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
import '../../../core/widgets/app_status_badge.dart';
import '../../../core/widgets/app_toast.dart';
import '../application/admin_labels.dart';
import '../application/admin_providers.dart';
import '../data/admin_resolve_models.dart';
import 'widgets/admin_action_dialogs.dart';
import 'widgets/admin_panel_widgets.dart';
import 'widgets/admin_stat_widgets.dart';

/// Avaliações (`/admin/avaliacoes`): moderar comentários. Ocultar não
/// apaga: a avaliação sai da app e das médias e pode ser reposta.
class AdminRatingsPage extends ConsumerStatefulWidget {
  const AdminRatingsPage({super.key});

  @override
  ConsumerState<AdminRatingsPage> createState() => _AdminRatingsPageState();
}

class _AdminRatingsPageState extends ConsumerState<AdminRatingsPage> {
  AdminRatingsQuery _query = (
    hidden: false,
    stars: null,
    onlyWithComment: false,
    page: 0,
  );

  void _set(AdminRatingsQuery query) => setState(() => _query = query);

  Future<void> _hide(AdminModerationRating rating) async {
    final done = await showAdminActionDialog(
      context,
      icon: Icons.visibility_off_outlined,
      title: 'Ocultar avaliação',
      consequence:
          'Deixa de aparecer na app e deixa de contar para a média de '
          '${rating.rateeName ?? 'quem foi avaliado'}. Não se apaga: podes '
          'repor. ${rating.raterName ?? 'Quem avaliou'} recebe um aviso com '
          'o motivo e como contestar.',
      confirmLabel: 'Ocultar',
      destructive: true,
      onSubmit: (input) => ref
          .read(adminRepositoryProvider)
          .hideRating(rating.ratingId, reason: input.reason!, note: input.note),
    );
    if (!done || !mounted) return;
    AppToast.of(context).show('Avaliação ocultada.');
    ref.invalidate(adminRatingsProvider);
  }

  Future<void> _restore(AdminModerationRating rating) async {
    final done = await showAdminActionDialog(
      context,
      icon: Icons.visibility_outlined,
      title: 'Repor avaliação',
      consequence:
          'Volta a aparecer na app e a contar para a média. Ninguém é '
          'avisado.',
      confirmLabel: 'Repor',
      askReason: false,
      noteLabel: 'Porquê (fica no registo)',
      onSubmit: (input) => ref
          .read(adminRepositoryProvider)
          .restoreRating(rating.ratingId, note: input.note),
    );
    if (!done || !mounted) return;
    AppToast.of(context).show('Avaliação reposta.');
    ref.invalidate(adminRatingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final ratingsAsync = ref.watch(adminRatingsProvider(_query));
    final textTheme = Theme.of(context).textTheme;
    final q = _query;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminRatingsProvider(q).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          Text(
            'Avaliações',
            style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppFilterChip(
                label: 'Visíveis',
                selected: !q.hidden,
                onPressed: () => _set((
                  hidden: false,
                  stars: q.stars,
                  onlyWithComment: q.onlyWithComment,
                  page: 0,
                )),
              ),
              AppFilterChip(
                label: 'Ocultas',
                leadingIcon: Icons.visibility_off_outlined,
                selected: q.hidden,
                onPressed: () => _set((
                  hidden: true,
                  stars: q.stars,
                  onlyWithComment: q.onlyWithComment,
                  page: 0,
                )),
              ),
              AppFilterChip(
                label: 'Com comentário',
                leadingIcon: Icons.chat_bubble_outline_rounded,
                selected: q.onlyWithComment,
                onPressed: () => _set((
                  hidden: q.hidden,
                  stars: q.stars,
                  onlyWithComment: !q.onlyWithComment,
                  page: 0,
                )),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppFilterChip(
                label: 'Todas as estrelas',
                selected: q.stars == null,
                onPressed: () => _set((
                  hidden: q.hidden,
                  stars: null,
                  onlyWithComment: q.onlyWithComment,
                  page: 0,
                )),
              ),
              for (final s in const [1, 2, 3, 4, 5])
                AppFilterChip(
                  label: '$s ★',
                  selected: q.stars == s,
                  onPressed: () => _set((
                    hidden: q.hidden,
                    stars: s,
                    onlyWithComment: q.onlyWithComment,
                    page: 0,
                  )),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ratingsAsync.when(
            loading: () => const AdminLoadingBlocks(count: 4, height: 96),
            error: (error, _) => AppInlineError(
              message: friendlyError(error),
              onRetry: () => ref.invalidate(adminRatingsProvider(q)),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return AppEmptyState(
                  icon: Icons.star_outline_rounded,
                  title: q.hidden ? 'Nenhuma oculta' : 'Nenhuma avaliação',
                  message: 'Nenhuma avaliação com estes filtros.',
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
                      child: AdminModerationRatingCard(
                        rating: row,
                        onOpenJob: row.jobId == null
                            ? null
                            : () => context.go('/admin/pedidos/${row.jobId}'),
                        onHide: row.hidden ? null : () => _hide(row),
                        onRestore: row.hidden ? () => _restore(row) : null,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  AdminPager(
                    page: q.page,
                    pages: (total / adminRatingsPageSize).ceil(),
                    onPage: (p) => _set((
                      hidden: q.hidden,
                      stars: q.stars,
                      onlyWithComment: q.onlyWithComment,
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

class AdminModerationRatingCard extends StatelessWidget {
  const AdminModerationRatingCard({
    required this.rating,
    required this.onOpenJob,
    required this.onHide,
    required this.onRestore,
    super.key,
  });

  final AdminModerationRating rating;
  final VoidCallback? onOpenJob;
  final VoidCallback? onHide;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final r = rating;
    return AdminPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${'★' * r.stars}${'☆' * (5 - r.stars).clamp(0, 5)}  '
                  '${r.raterName ?? 'Sem nome'} → ${r.rateeName ?? 'Sem nome'}',
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (r.hidden)
                const AppStatusBadge(
                  label: 'Oculta',
                  statusColor: AppStatusColor.neutral,
                  dense: true,
                ),
            ],
          ),
          if (r.comment != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '"${r.comment}"',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxs),
          Text(
            [
              adminDateTimeLabel(r.createdAt),
              if (r.hidden)
                'oculta a ${adminDateTimeLabel(r.hiddenAt)}: '
                    '${AdminActionReason.labelOf(r.hiddenReason)}',
            ].join(' · '),
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              if (onOpenJob != null)
                TextButton.icon(
                  onPressed: onOpenJob,
                  icon: const Icon(Icons.assignment_outlined, size: 18),
                  label: const Text('Ver pedido'),
                ),
              if (onHide != null)
                TextButton.icon(
                  onPressed: onHide,
                  icon: const Icon(Icons.visibility_off_outlined, size: 18),
                  label: const Text('Ocultar'),
                ),
              if (onRestore != null)
                TextButton.icon(
                  onPressed: onRestore,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Repor'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
