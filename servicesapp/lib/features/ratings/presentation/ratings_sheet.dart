import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/rating_providers.dart';

/// Opens a read-only bottom sheet showing a worker's average rating and
/// the list of individual ratings with rater names and comments.
/// Uses Consumer internally — no WidgetRef needed from the call site.
Future<void> showRatingsSheet(
  BuildContext context, {
  required String workerId,
  required String workerName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => Consumer(
      builder: (ctx, ref, _) {
        final summaryAsync = ref.watch(ratingSummaryProvider(workerId));
        final ratingsAsync = ref.watch(ratingsWithNamesProvider(workerId));

        return DraggableScrollableSheet(
          initialChildSize: 0.55,
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
                          loading: () => const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (_, _) => const SizedBox.shrink(),
                          data: (summary) => _RatingHeader(
                            workerName: workerName,
                            summary: summary,
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: Divider(height: 1)),
                      ratingsAsync.when(
                        loading: () => const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                        error: (_, _) => const SliverToBoxAdapter(
                            child: SizedBox.shrink()),
                        data: (ratings) {
                          final withComment = ratings
                              .where((r) =>
                                  r.comment != null && r.comment!.isNotEmpty)
                              .toList();
                          if (withComment.isEmpty) {
                            return const SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Padding(
                                  padding: EdgeInsets.all(32),
                                  child: Text('Ainda sem avaliações.'),
                                ),
                              ),
                            );
                          }
                          return SliverList.separated(
                            itemCount: withComment.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1, indent: 16),
                            itemBuilder: (ctx, i) =>
                                _RatingRow(rating: withComment[i]),
                          );
                        },
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _RatingHeader extends StatelessWidget {
  const _RatingHeader({required this.workerName, required this.summary});

  final String workerName;
  final RatingSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasRatings = summary.ratingCount > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(workerName, style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          if (!hasRatings)
            Text(
              'Ainda sem avaliações.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  summary.avgRating.toStringAsFixed(1),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: List.generate(5, (i) {
                        final filled = i < summary.avgRating.round();
                        return Icon(
                          filled ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: 20,
                          color: Colors.amber,
                        );
                      }),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${summary.ratingCount} '
                      'avalia${summary.ratingCount == 1 ? 'ção' : 'ções'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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

class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.rating});

  final Rating rating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rating.raterName ?? '—',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  final filled = i < rating.stars;
                  return Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 14,
                    color: Colors.amber,
                  );
                }),
              ),
            ],
          ),
          if (rating.comment != null && rating.comment!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              rating.comment!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
