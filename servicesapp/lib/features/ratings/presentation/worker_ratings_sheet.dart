import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/price_labels.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../worker/application/worker_providers.dart';
import '../../worker/presentation/widgets/worker_showcase_section.dart';
import '../application/rating_providers.dart';

/// Opens a read-only bottom sheet showing a worker's average rating, what
/// the worker chose to highlight (bio, destaques e links, migration 0051)
/// and the list of individual ratings with rater names and comments.
/// Uses Consumer internally — no WidgetRef needed from the call site.
Future<void> showWorkerRatingsSheet(
  BuildContext context, {
  required String workerId,
  required String workerName,
}) {
  // Fundo cinzento da app com cartões brancos, como os outros ecrãs (o
  // fundo por omissão do Material ficava esverdeado e desencontrado).
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (_) => Consumer(
      builder: (ctx, ref, _) {
        final summaryAsync = ref.watch(ratingSummaryProvider(workerId));
        final ratingsAsync = ref.watch(ratingsWithNamesProvider(workerId));
        // Destaques: se falhar ou ainda não houver, a folha mostra só as
        // avaliações, como antes.
        final card = ref.watch(workerPublicCardProvider(workerId)).asData?.value;

        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          expand: false,
          builder: (ctx, scrollController) {
            return Column(
              children: [
                _SheetHandle(),
                Expanded(
                  child: CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: summaryAsync.when(
                          loading: () => Padding(
                            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
                            child: AppSkeletonShimmer(
                              child: SizedBox(
                                width: double.infinity,
                                height: 112,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.input),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          error: (_, _) => const SizedBox.shrink(),
                          data: (summary) => _RatingHeader(
                            workerName: workerName,
                            avatarUrl: card?.avatarUrl,
                            locationName: card?.locationName,
                            serviceNames: card?.serviceNames ?? const [],
                            summary: summary,
                            onClose: () => Navigator.pop(ctx),
                          ),
                        ),
                      ),
                      if (card != null)
                        SliverToBoxAdapter(
                          child: AppStaggeredEntrance(
                            index: 0,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.md,
                                0,
                                AppSpacing.md,
                                AppSpacing.md,
                              ),
                              child: WorkerShowcaseSection(
                                bio: card.bio,
                                highlights: card.highlights,
                                socialLinks: card.socialLinks,
                              ),
                            ),
                          ),
                        ),
                                            ratingsAsync.when(
                        loading: () => SliverPadding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          sliver: SliverList.list(
                            children: [
                              for (var i = 0; i < 3; i++) ...[
                                AppSkeletonShimmer(
                                  child: Container(
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(
                                          AppRadius.input),
                                    ),
                                  ),
                                ),
                                if (i < 2) const SizedBox(height: AppSpacing.sm),
                              ],
                            ],
                          ),
                        ),
                        error: (_, _) => const SliverToBoxAdapter(
                            child: SizedBox.shrink()),
                        data: (ratings) {
                          if (ratings.isEmpty) {
                            return const SliverFillRemaining(
                              hasScrollBody: false,
                              child: Padding(
                                padding: EdgeInsets.all(AppSpacing.lg),
                                child: AppEmptyState(
                                  icon: Icons.star_outline_rounded,
                                  title: 'Ainda sem avaliações',
                                  message:
                                      'As avaliações dos clientes aparecem aqui.',
                                  tone: AppStatusColor.neutral,
                                ),
                              ),
                            );
                          }
                          // Design U6: um cartão por avaliação, com ou sem
                          // comentário (as estrelas contam por si).
                          return SliverPadding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              AppSpacing.xs,
                              AppSpacing.md,
                              0,
                            ),
                            sliver: SliverList.separated(
                              itemCount: ratings.length + 1,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: AppSpacing.sm),
                              itemBuilder: (ctx, index) {
                                if (index == 0) {
                                  return _SectionLabel(
                                    'AVALIAÇÕES · ${ratings.length}',
                                  );
                                }
                                final i = index - 1;
                                final row = _RatingRow(rating: ratings[i]);
                                // Stagger só nos primeiros, para não atrasar
                                // listas longas.
                                return i < 6
                                    ? AppStaggeredEntrance(index: i, child: row)
                                    : row;
                              },
                            ),
                          );
                        },
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Container(
        width: AppSizes.sheetHandleWidth,
        height: AppSizes.sheetHandleHeight,
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xxs),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}

/// Cartão do topo: foto, nome, zona, nota média e serviços do jardineiro.
class _RatingHeader extends StatelessWidget {
  const _RatingHeader({
    required this.workerName,
    required this.summary,
    required this.onClose,
    this.avatarUrl,
    this.locationName,
    this.serviceNames = const [],
  });

  final String workerName;
  final String? avatarUrl;
  final String? locationName;
  final List<String> serviceNames;
  final RatingSummary summary;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasRatings = summary.ratingCount > 0;
    final name = workerName.trim().isEmpty ? 'Jardineiro' : workerName.trim();
    final location = locationName?.trim() ?? '';
    final hasAvatar = avatarUrl != null && avatarUrl!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: AppSizes.avatarSmall / 2 + AppSpacing.xxs,
                  backgroundColor: AppColors.primaryContainer,
                  backgroundImage: hasAvatar ? NetworkImage(avatarUrl!) : null,
                  child: hasAvatar
                      ? null
                      : Text(
                          name.characters.first.toUpperCase(),
                          style: textTheme.titleMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleLarge
                            ?.copyWith(color: AppColors.textPrimary),
                      ),
                      Text(
                        location.isEmpty ? 'Jardineiro' : 'Jardineiro · $location',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: onClose,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: hasRatings
                  ? Row(
                      children: [
                        Text(
                          decimalLabel(summary.avgRating, 1),
                          style: textTheme.headlineSmall?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        ...List.generate(5, (i) {
                          final filled = i < summary.avgRating.round();
                          return Icon(
                            filled
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: AppSizes.infoRowIcon,
                            color: AppColors.logoAccent,
                          );
                        }),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            '${summary.ratingCount} '
                            'avalia${summary.ratingCount == 1 ? 'ção' : 'ções'}',
                            textAlign: TextAlign.end,
                            style: textTheme.bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Ainda sem avaliações.',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
            ),
            if (serviceNames.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final service in serviceNames)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        service,
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.primaryPressed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.rating});

  final Rating rating;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final name = rating.raterName?.trim().isNotEmpty == true
        ? rating.raterName!.trim()
        : 'Cliente';
    final comment = rating.comment?.trim();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: AppSizes.reviewAvatar,
                height: AppSizes.reviewAvatar,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  name.characters.first.toUpperCase(),
                  style: textTheme.labelLarge?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      DateFormat('dd/MM/yyyy').format(rating.createdAt.toLocal()),
                      style: textTheme.labelMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  final filled = i < rating.stars;
                  return Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: AppSizes.ratingStar,
                    color: AppColors.logoAccent,
                  );
                }),
              ),
            ],
          ),
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              comment,
              style:
                  textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
            ),
          ],
        ],
      ),
    );
  }
}
