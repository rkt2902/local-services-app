import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_back_navigation.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/price_labels.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../auth/application/auth_providers.dart';
import '../../../core/widgets/primary_action_button.dart';
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
        title: Text(
          'Perfil',
          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        ),
      ),
      bottomNavigationBar: isVisitor
          ? SafeArea(
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
            )
          : null,
      body: cardAsync.when(
        loading: () => const AppScreenLoadingSkeleton(),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (card) {
          if (card == null) {
            return const Center(child: Text('Perfil não encontrado.'));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: Column(
              children: [
                AppStaggeredEntrance(
                  index: 0,
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: AppColors.primaryContainer,
                    backgroundImage: card.avatarUrl != null
                        ? NetworkImage(card.avatarUrl!)
                        : null,
                    child: card.avatarUrl == null
                        ? const Icon(
                            Icons.person_outline_rounded,
                            size: 40,
                            color: AppColors.primary,
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppStaggeredEntrance(
                  index: 1,
                  child: Text(
                    card.fullName,
                    textAlign: TextAlign.center,
                    style:
                        textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
                  ),
                ),
                if (card.locationName.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    card.locationName,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                AppStaggeredEntrance(
                  index: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 18, color: AppColors.logoAccent),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        card.ratingCount > 0
                            ? '${decimalLabel(card.avgRating, 1)} (${card.ratingCount})'
                            : 'Sem avaliações ainda',
                        style: textTheme.bodyMedium
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (card.bio != null && card.bio!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppStaggeredEntrance(
                    index: 3,
                    child: Text(
                      card.bio!,
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                ],
                if (card.serviceNames.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppStaggeredEntrance(
                    index: 4,
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
                if (card.highlights.isNotEmpty ||
                    card.socialLinks.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppStaggeredEntrance(
                    index: 5,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: AppColors.divider),
                      ),
                      // A apresentação já aparece acima, centrada.
                      child: WorkerShowcaseSection(
                        highlights: card.highlights,
                        socialLinks: card.socialLinks,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
