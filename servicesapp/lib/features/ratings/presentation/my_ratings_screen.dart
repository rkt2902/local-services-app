import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/widgets/app_motion.dart';

/// Ecrã genérico "As minhas avaliações" — 2 tabs (Recebidas/Dadas), usado
/// tanto pelo cliente como pelo worker. Não sabe qual dos dois papéis está
/// a olhar para ele: recebe tudo já resolvido em ViewData pelo ecrã
/// wrapper de cada lado (`WorkerRatingsScreen`/`ClientRatingsScreen`).
///
/// Estrutura visual portada de doc.txt (referência), com os nomes
/// generalizados (deixou de ser `WorkerReviews*`) e sem paginação — as
/// listas vêm inteiras de `get_my_ratings_received`/`get_my_ratings_given`,
/// por isso `animateEntrance` é sempre `true` aqui (o campo fica pronto
/// para paginação futura, mas hoje nunca chega `false`).
enum MyRatingsTab {
  received,
  given,
}

class MyRatingsSummaryViewData {
  const MyRatingsSummaryViewData({
    required this.averageRatingLabel,
    required this.receivedReviewsLabel,
    required this.filledSummaryStars,
    required this.maxSummaryStars,
    required this.hasReceivedReviews,
  });

  final String averageRatingLabel;
  final String receivedReviewsLabel;
  final int filledSummaryStars;
  final int maxSummaryStars;
  final bool hasReceivedReviews;
}

class ReceivedRatingViewData {
  const ReceivedRatingViewData({
    required this.ratingId,
    required this.raterName,
    required this.dateLabel,
    required this.filledStars,
    required this.maxStars,
    required this.comment,
    required this.serviceLabel,
    required this.serviceIcon,
    this.raterAvatarUrl,
    this.animateEntrance = true,
  });

  final String ratingId;
  final String raterName;
  final String? raterAvatarUrl;
  final String dateLabel;
  final int filledStars;
  final int maxStars;
  final String? comment;
  final String serviceLabel;
  final IconData serviceIcon;
  final bool animateEntrance;
}

class GivenRatingViewData {
  const GivenRatingViewData({
    required this.ratingId,
    required this.rateeName,
    required this.dateLabel,
    required this.filledStars,
    required this.maxStars,
    required this.comment,
    required this.serviceLabel,
    required this.serviceIcon,
    this.rateeAvatarUrl,
    this.animateEntrance = true,
  });

  final String ratingId;
  final String rateeName;
  final String? rateeAvatarUrl;
  final String dateLabel;
  final int filledStars;
  final int maxStars;
  final String? comment;
  final String serviceLabel;
  final IconData serviceIcon;
  final bool animateEntrance;
}

class MyRatingsScreen extends StatefulWidget {
  const MyRatingsScreen({
    super.key,
    required this.summaryAsync,
    required this.receivedAsync,
    required this.givenAsync,
    required this.receivedTabLabel,
    required this.givenTabLabel,
    required this.onBack,
    this.initialTab = MyRatingsTab.received,
    this.onTabChanged,
    this.onRetrySummary,
    this.onRetryReceived,
    this.onRetryGiven,
  });

  /// Cabeçalho de reputação, igual nas duas tabs — a média vem sempre das
  /// avaliações recebidas.
  final AsyncValue<MyRatingsSummaryViewData> summaryAsync;

  final AsyncValue<List<ReceivedRatingViewData>> receivedAsync;
  final AsyncValue<List<GivenRatingViewData>> givenAsync;

  final String receivedTabLabel;
  final String givenTabLabel;

  final MyRatingsTab initialTab;

  final VoidCallback onBack;

  final ValueChanged<MyRatingsTab>? onTabChanged;

  final VoidCallback? onRetrySummary;
  final VoidCallback? onRetryReceived;
  final VoidCallback? onRetryGiven;

  @override
  State<MyRatingsScreen> createState() => _MyRatingsScreenState();
}

class _MyRatingsScreenState extends State<MyRatingsScreen> {
  late MyRatingsTab _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  @override
  void didUpdateWidget(covariant MyRatingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.initialTab != widget.initialTab) {
      _selectedTab = widget.initialTab;
    }
  }

  void _selectTab(MyRatingsTab tab) {
    if (_selectedTab == tab) {
      return;
    }

    setState(() {
      _selectedTab = tab;
    });

    widget.onTabChanged?.call(tab);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _RatingsHeader(
              summaryAsync: widget.summaryAsync,
              onBack: widget.onBack,
              onRetry: widget.onRetrySummary,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: _RatingsTabs(
                selectedTab: _selectedTab,
                receivedLabel: widget.receivedTabLabel,
                givenLabel: widget.givenTabLabel,
                onSelected: _selectTab,
              ),
            ),
            Expanded(
              child: AppFadeThroughSwitcher(
                switchKey: _selectedTab,
                duration: const Duration(milliseconds: 220),
                child: _selectedTab == MyRatingsTab.received
                    ? _ReceivedTab(
                        key: const ValueKey('my_ratings_received'),
                        reviewsAsync: widget.receivedAsync,
                        onRetry: widget.onRetryReceived,
                      )
                    : _GivenTab(
                        key: const ValueKey('my_ratings_given'),
                        reviewsAsync: widget.givenAsync,
                        onRetry: widget.onRetryGiven,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// HEADER
// -----------------------------------------------------------------------------

class _RatingsHeader extends StatelessWidget {
  const _RatingsHeader({
    required this.summaryAsync,
    required this.onBack,
    required this.onRetry,
  });

  final AsyncValue<MyRatingsSummaryViewData> summaryAsync;
  final VoidCallback onBack;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(
                  Icons.arrow_back,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  'Avaliações',
                  style: textTheme.titleLarge?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
            ),
            child: summaryAsync.when(
              loading: () => const _SummarySkeleton(),
              error: (_, _) => _SummaryUnavailable(onRetry: onRetry),
              data: (summary) => _SummaryContent(summary: summary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryContent extends StatelessWidget {
  const _SummaryContent({required this.summary});

  final MyRatingsSummaryViewData summary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          summary.averageRatingLabel,
          style: textTheme.displaySmall?.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (summary.hasReceivedReviews)
                _StarsRow(
                  filledStars: summary.filledSummaryStars,
                  maxStars: summary.maxSummaryStars,
                  size: 18,
                ),
              if (summary.hasReceivedReviews)
                const SizedBox(height: AppSpacing.xxs),
              Text(
                summary.receivedReviewsLabel,
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppSkeletonShimmer(
          child: Container(
            width: 64,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeletonShimmer(
                child: Container(
                  width: 112,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              AppSkeletonShimmer(
                child: Container(
                  width: 84,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryUnavailable extends StatelessWidget {
  const _SummaryUnavailable({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Text(
          '—',
          style: textTheme.displaySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Reputação indisponível',
            style: textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        if (onRetry != null)
          IconButton(
            onPressed: onRetry,
            icon: const Icon(
              Icons.refresh_rounded,
              color: AppColors.primary,
            ),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// TABS
// -----------------------------------------------------------------------------

class _RatingsTabs extends StatelessWidget {
  const _RatingsTabs({
    required this.selectedTab,
    required this.receivedLabel,
    required this.givenLabel,
    required this.onSelected,
  });

  final MyRatingsTab selectedTab;
  final String receivedLabel;
  final String givenLabel;
  final ValueChanged<MyRatingsTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.divider,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: receivedLabel,
              selected: selectedTab == MyRatingsTab.received,
              onPressed: () => onSelected(MyRatingsTab.received),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: _TabButton(
              label: givenLabel,
              selected: selectedTab == MyRatingsTab.given,
              onPressed: () => onSelected(MyRatingsTab.given),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: selected ? AppColors.surface : AppColors.background,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: selected ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// RECEBIDAS
// -----------------------------------------------------------------------------

class _ReceivedTab extends StatelessWidget {
  const _ReceivedTab({
    super.key,
    required this.reviewsAsync,
    required this.onRetry,
  });

  final AsyncValue<List<ReceivedRatingViewData>> reviewsAsync;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return reviewsAsync.when(
      loading: () => const _RatingsListSkeleton(),
      error: (_, _) => _RatingsError(onRetry: onRetry),
      data: (reviews) {
        if (reviews.isEmpty) {
          return const _ReceivedEmptyState();
        }

        return ListView.separated(
          key: const PageStorageKey('my_ratings_received'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xxs,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          itemCount: reviews.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            final review = reviews[index];
            final card = _ReceivedRatingCard(review: review);

            if (!review.animateEntrance) {
              return card;
            }

            return AppStaggeredEntrance(index: index, child: card);
          },
        );
      },
    );
  }
}

class _ReceivedRatingCard extends StatelessWidget {
  const _ReceivedRatingCard({required this.review});

  final ReceivedRatingViewData review;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(avatarUrl: review.raterAvatarUrl),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.raterName,
                      style: textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      review.dateLabel,
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _StarsRow(
                filledStars: review.filledStars,
                maxStars: review.maxStars,
                size: 16,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _ExpandableComment(comment: review.comment),
          const SizedBox(height: AppSpacing.sm),
          _ServiceLine(icon: review.serviceIcon, label: review.serviceLabel),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// DADAS
// -----------------------------------------------------------------------------

class _GivenTab extends StatelessWidget {
  const _GivenTab({
    super.key,
    required this.reviewsAsync,
    required this.onRetry,
  });

  final AsyncValue<List<GivenRatingViewData>> reviewsAsync;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return reviewsAsync.when(
      loading: () => const _RatingsListSkeleton(),
      error: (_, _) => _RatingsError(onRetry: onRetry),
      data: (reviews) {
        if (reviews.isEmpty) {
          return const _GivenEmptyState();
        }

        return ListView.separated(
          key: const PageStorageKey('my_ratings_given'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xxs,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          itemCount: reviews.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            final review = reviews[index];
            final card = _GivenRatingCard(review: review);

            if (!review.animateEntrance) {
              return card;
            }

            return AppStaggeredEntrance(index: index, child: card);
          },
        );
      },
    );
  }
}

class _GivenRatingCard extends StatelessWidget {
  const _GivenRatingCard({required this.review});

  final GivenRatingViewData review;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(avatarUrl: review.rateeAvatarUrl),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Avaliaste',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      review.rateeName,
                      style: textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _StarsRow(
                filledStars: review.filledStars,
                maxStars: review.maxStars,
                size: 16,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _ExpandableComment(comment: review.comment),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _ServiceLine(
                  icon: review.serviceIcon,
                  label: review.serviceLabel,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                review.dateLabel,
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// COMMENT
// -----------------------------------------------------------------------------

class _ExpandableComment extends StatefulWidget {
  const _ExpandableComment({required this.comment});

  final String? comment;

  @override
  State<_ExpandableComment> createState() => _ExpandableCommentState();
}

class _ExpandableCommentState extends State<_ExpandableComment> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _ExpandableComment oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.comment != widget.comment) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final comment = widget.comment?.trim();

    if (comment == null || comment.isEmpty) {
      return Text(
        'Sem comentário.',
        style: textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final style = textTheme.bodyMedium?.copyWith(
          color: AppColors.textPrimary,
        );

        final painter = TextPainter(
          text: TextSpan(text: comment, style: style),
          maxLines: 3,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);

        final needsExpansion = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              comment,
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: style,
            ),
            if (needsExpansion && !_expanded) ...[
              const SizedBox(height: AppSpacing.xxs),
              TextButton(
                onPressed: () => setState(() => _expanded = true),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Ver mais',
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// SHARED CARD PIECES
// -----------------------------------------------------------------------------

class _Avatar extends StatelessWidget {
  const _Avatar({required this.avatarUrl});

  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.primaryContainer,
      backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl!),
      child: avatarUrl == null
          ? const Icon(
              Icons.person_outline_rounded,
              color: AppColors.primary,
            )
          : null,
    );
  }
}

class _StarsRow extends StatelessWidget {
  const _StarsRow({
    required this.filledStars,
    required this.maxStars,
    required this.size,
  });

  final int filledStars;
  final int maxStars;
  final double size;

  @override
  Widget build(BuildContext context) {
    final safeMax = maxStars < 0 ? 0 : maxStars;
    final safeFilled = filledStars.clamp(0, safeMax).toInt();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(safeMax, (index) {
        final filled = index < safeFilled;
        return Icon(
          filled ? Icons.star_rounded : Icons.star_border_rounded,
          size: size,
          color: AppColors.logoAccent,
        );
      }),
    );
  }
}

class _ServiceLine extends StatelessWidget {
  const _ServiceLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// EMPTY STATES
// -----------------------------------------------------------------------------

class _ReceivedEmptyState extends StatelessWidget {
  const _ReceivedEmptyState();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppStaggeredEntrance(
          index: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: AppColors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.star_border_rounded,
                  size: 34,
                  color: AppColors.logoAccent,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Ainda não recebeste avaliações',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'As avaliações aparecem aqui depois de cada trabalho concluído.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GivenEmptyState extends StatelessWidget {
  const _GivenEmptyState();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppStaggeredEntrance(
          index: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: AppColors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.rate_review_outlined,
                  size: 32,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Ainda não avaliaste ninguém',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Quando avaliares alguém após um trabalho, fica registado aqui.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// LOADING
// -----------------------------------------------------------------------------

class _RatingsListSkeleton extends StatelessWidget {
  const _RatingsListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xxs,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      itemCount: 3,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, _) {
        return AppSkeletonShimmer(
          child: Container(
            height: 134,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// ERROR
// -----------------------------------------------------------------------------

class _RatingsError extends StatelessWidget {
  const _RatingsError({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppStaggeredEntrance(
          index: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: AppStatusColor.cancelled.background,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.cloud_off_outlined,
                  size: 32,
                  color: AppStatusColor.cancelled.foreground,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Não foi possível carregar',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Verifica a ligação e tenta novamente.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.divider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                    ),
                  ),
                  child: Text(
                    'Tentar novamente',
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
