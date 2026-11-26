import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';

/// Topo dos passos do registo do Profissional: voltar (se houver para onde),
/// "Passo X de Y" e uma barra por passo, cheias até ao atual.
class WorkerSetupStepHeader extends StatelessWidget {
  const WorkerSetupStepHeader({
    required this.step,
    required this.totalSteps,
    this.onBack,
    super.key,
  });

  final int step;
  final int totalSteps;

  /// `null` esconde a seta (primeiro passo, sem nada para trás).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.s10, AppSpacing.xs, AppSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: AppSizes.minTapTarget,
            child: Row(
              children: [
                if (onBack != null)
                  IconButton(
                    tooltip: 'Voltar',
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.textPrimary),
                  ),
                const Spacer(),
                Text(
                  'Passo $step de $totalSteps',
                  style: textTheme.labelLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
                left: AppSpacing.s14, bottom: AppSpacing.xs),
            child: Semantics(
              label: 'Passo $step de $totalSteps',
              excludeSemantics: true,
              child: Row(
                children: [
                  for (var i = 1; i <= totalSteps; i++) ...[
                    if (i > 1) const SizedBox(width: AppSpacing.s6),
                    Expanded(
                      child: AnimatedContainer(
                        duration: disableAnimations
                            ? Duration.zero
                            : AppMotionDuration.screen,
                        curve: AppMotionCurve.standard,
                        height: AppSizes.stepSegmentHeight,
                        decoration: BoxDecoration(
                          color:
                              i <= step ? AppColors.primary : AppColors.divider,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
