import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_back_navigation.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/price_labels.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../auth/application/auth_providers.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../ratings/presentation/worker_ratings_sheet.dart';
import '../application/worker_providers.dart';
import 'widgets/worker_showcase_section.dart';

/// Perfil público mínimo do worker — acessível via link/QR partilhado a
/// partir do cartão digital, sem sessão. Ver `worker_public_card` (migration
/// 0033) para a origem dos dados e o que fica deliberadamente de fora
/// (telefone, morada exata, raio de atuação).
class WorkerPublicProfileScreen extends ConsumerWidget {
  const WorkerPublicProfileScreen({required this.workerId, super.key});

  final String workerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardAsync = ref.watch(workerPublicCardProvider(workerId));
    final textTheme = Theme.of(context).textTheme;
    // Visitante sem conta (link/QR partilhado): voltar leva ao início
    // público e há um convite para criar conta.
    final isVisitor = ref.watch(currentUserIdProvider) == null;

    void back() => isVisitor
        ? goBackOr(context, '/')
        : goBackOrToRoleHome(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          onPressed: back,
          tooltip: 'Voltar',
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      bottomNavigationBar: isVisitor
          ? ColoredBox(
              color: AppColors.surface,
              child: SafeArea(
                child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                  child: PrimaryActionButton(
                    label: 'Criar conta',
                    onPressed: () => context.go('/signup'),
                  ),
                ),
              ),
            )
          : null,
      body: cardAsync.when(
        loading: () => const AppScreenLoadingSkeleton(),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (card) {
          if (card == null) {
            return const Center(child: Text('Perfil não encontrado.'));
          }
          final hasRatings = card.ratingCount > 0;
          final ratingStyle =
              textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);
          final ratingRow = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.star_rounded,
                size: AppSizes.inlineIcon,
                color: AppColors.logoAccent,
              ),
              const SizedBox(width: AppSpacing.xxs),
              if (hasRatings) ...[
                Text(
                  decimalLabel(card.avgRating, 1),
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  ' · ${card.ratingCount} '
                  'avalia${card.ratingCount == 1 ? 'ção' : 'ções'}',
                  style: ratingStyle,
                ),
              ] else
                Text('Sem avaliações ainda', style: ratingStyle),
            ],
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppStaggeredEntrance(
                  index: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.xxs),
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        radius: AppSizes.publicAvatar / 2,
                        backgroundColor: AppColors.primaryContainer,
                        backgroundImage: card.avatarUrl != null
                            ? NetworkImage(card.avatarUrl!)
                            : null,
                        child: card.avatarUrl == null
                            ? const Icon(
                                Icons.person_outline_rounded,
                                size: AppSizes.emptyIcon,
                                color: AppColors.primary,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppStaggeredEntrance(
                  index: 1,
                  child: Column(
                    children: [
                      Text(
                        card.fullName,
                        textAlign: TextAlign.center,
                        style: textTheme.titleLarge?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      // Só a zona: o raio fica de fora do cartão público
                      // (worker_public_card, 0033).
                      if (card.locationName.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          card.locationName,
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xxs),
                      // As avaliações individuais só se leem com sessão
                      // (RLS de ratings); o visitante vê só a média.
                      if (hasRatings && !isVisitor)
                        InkWell(
                          onTap: () => showWorkerRatingsSheet(
                            context,
                            workerId: card.workerId,
                            workerName: card.fullName,
                          ),
                          borderRadius:
                              BorderRadius.circular(AppRadius.input),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xxs),
                            child: ratingRow,
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.xxs),
                          child: ratingRow,
                        ),
                    ],
                  ),
                ),
                if (card.serviceNames.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppStaggeredEntrance(
                    index: 2,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: card.serviceNames
                          .map((name) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: AppSpacing.xs,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryContainer,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.pill),
                                ),
                                child: Text(
                                  name,
                                  style: textTheme.labelMedium
                                      ?.copyWith(color: AppColors.primary),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                AppStaggeredEntrance(
                  index: 3,
                  child: WorkerShowcaseSection(
                    bio: card.bio,
                    highlights: card.highlights,
                    socialLinks: card.socialLinks,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
