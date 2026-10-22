import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_initials_avatar.dart';
import '../../../../core/widgets/app_inline_error.dart';
import '../../../../core/widgets/app_motion.dart';

/// "Os teus jardineiros" no Início do cliente (design A5, 4): jardineiros
/// com quem já concluiu trabalhos, numa lista horizontal com cerca de dois
/// cartões à vista. Lista vazia: a secção não aparece.
class YourGardenerCardViewData {
  const YourGardenerCardViewData({
    required this.workerId,
    required this.workerName,
    required this.workerInitial,
    required this.lastServiceLabel,
    required this.lastWorkedLabel,
    this.workerAvatarUrl,
  });

  final String workerId;
  final String workerName;
  final String workerInitial;
  final String? workerAvatarUrl;
  final String lastServiceLabel;

  /// "há 3 semanas".
  final String lastWorkedLabel;
}

class YourGardenersSection extends StatelessWidget {
  const YourGardenersSection({
    super.key,
    required this.dataAsync,
    required this.onRepeatHire,
    this.onRetry,
  });

  static const title = 'Os teus jardineiros';

  final AsyncValue<List<YourGardenerCardViewData>> dataAsync;
  final ValueChanged<YourGardenerCardViewData> onRepeatHire;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return dataAsync.when(
      loading: () => const _YourGardenersSkeleton(),
      error: (_, _) => _SectionFrame(
        child: AppInlineError(
          message: 'Não foi possível carregar os teus jardineiros.',
          onRetry: onRetry,
        ),
      ),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return _SectionFrame(
          child: _GardenersList(items: items, onRepeatHire: onRepeatHire),
        );
      },
    );
  }
}

/// Título da secção e o conteúdo por baixo, com o espaço até à secção
/// seguinte (assim, sem secção, também não fica espaço).
class _SectionFrame extends StatelessWidget {
  const _SectionFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            YourGardenersSection.title,
            style: textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _GardenersList extends StatelessWidget {
  const _GardenersList({required this.items, required this.onRepeatHire});

  final List<YourGardenerCardViewData> items;
  final ValueChanged<YourGardenerCardViewData> onRepeatHire;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Dois cartões à vista e um pedaço do terceiro, quando há mais.
        final visible = items.length > 2 ? 2.2 : 2.0;
        final itemWidth =
            (constraints.maxWidth - AppSpacing.xs * (visible.ceil() - 1)) /
                visible;

        return SizedBox(
          height: AppSizes.gardenerCardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
            itemBuilder: (context, index) {
              final item = items[index];
              return SizedBox(
                width: itemWidth,
                child: _GardenerCard(
                  item: item,
                  onPressed: () => onRepeatHire(item),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _GardenerCard extends StatelessWidget {
  const _GardenerCard({required this.item, required this.onPressed});

  final YourGardenerCardViewData item;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppInitialsAvatar(
                initial: item.workerInitial,
                avatarUrl: item.workerAvatarUrl,
                radius: AppSizes.gardenerAvatarRadius,
                textStyle: textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                item.workerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                item.lastServiceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                item.lastWorkedLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Pedir de novo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelLarge?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: AppSizes.inlineIcon,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YourGardenersSkeleton extends StatelessWidget {
  const _YourGardenersSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget card() => Expanded(
          child: AppSkeletonShimmer(
            child: Container(
              height: AppSizes.gardenerCardHeight,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSkeletonShimmer(
            child: Container(
              width: AppSizes.gardenerSkeletonTitleWidth,
              height: AppSpacing.s18,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              card(),
              const SizedBox(width: AppSpacing.xs),
              card(),
            ],
          ),
        ],
      ),
    );
  }
}
