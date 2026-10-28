import 'package:flutter/material.dart';

import '../constants/enums.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// Selo do plano do jardineiro ao lado do nome: "Pro" contornado a dourado,
/// "Pro+" cheio a dourado. No Grátis não aparece nada.
///
/// Usado nas propostas, no cartão público, no Perfil e no cartão
/// partilhável, para o selo ser igual em todo o lado.
class AppPlanBadge extends StatelessWidget {
  const AppPlanBadge({super.key, required this.tier, this.large = false});

  final WorkerPlanTier tier;

  /// `labelMedium` em vez de `labelSmall` (cartão público e cartão
  /// partilhável).
  final bool large;

  @override
  Widget build(BuildContext context) {
    if (!tier.isPaid) return const SizedBox.shrink();
    final filled = tier == WorkerPlanTier.proPlus;
    final textTheme = Theme.of(context).textTheme;
    final style = (large ? textTheme.labelMedium : textTheme.labelSmall)
        ?.copyWith(
      color: filled ? AppColors.surface : AppColors.textPrimary,
      fontWeight: FontWeight.w700,
    );
    return Semantics(
      label: 'Plano ${tier.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: filled ? AppColors.logoAccent : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.logoAccent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.workspace_premium_rounded,
              size: style?.fontSize,
              color: filled ? AppColors.surface : AppColors.logoAccent,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(tier.label, style: style),
          ],
        ),
      ),
    );
  }
}
