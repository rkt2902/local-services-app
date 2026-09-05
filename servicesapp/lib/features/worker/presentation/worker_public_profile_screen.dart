import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_motion.dart';
import '../application/worker_providers.dart';

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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        title: Text(
          'Perfil',
          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        ),
      ),
      body: cardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
                            ? '${card.avgRating.toStringAsFixed(1)} (${card.ratingCount})'
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
              ],
            ),
          );
        },
      ),
    );
  }
}
