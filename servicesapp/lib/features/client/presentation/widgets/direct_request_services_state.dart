import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_motion.dart';

// Passo 1 do pedido pelo cartão (A7): os serviços do jardineiro a carregar,
// sem nenhum, ou com erro.

class DirectRequestServicesSkeleton extends StatelessWidget {
  const DirectRequestServicesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < 3; index++) ...[
          AppSkeletonShimmer(
            child: Container(
              height: AppSizes.directServiceSkeleton,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
            ),
          ),
          if (index < 2) const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

class DirectRequestServicesEmpty extends StatelessWidget {
  const DirectRequestServicesEmpty({
    super.key,
    required this.workerName,
    required this.onShowAllServices,
  });

  /// Primeiro nome.
  final String workerName;
  final VoidCallback onShowAllServices;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.work_outline_rounded,
      title: '$workerName ainda não indicou serviços',
      message: 'Podes escolher entre todos os serviços. O pedido continua a '
          'ir primeiro para $workerName.',
      actionLabel: 'Ver todos os serviços',
      onAction: onShowAllServices,
      tone: AppStatusColor.neutral,
    );
  }
}

class DirectRequestServicesError extends StatelessWidget {
  const DirectRequestServicesError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: AppStatusColor.cancelled.foreground,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Não foi possível carregar os serviços.',
              style: textTheme.labelMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'Tentar novamente',
              style: textTheme.labelMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
