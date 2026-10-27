import 'package:flutter/material.dart';

import '../models/job_flow_stage.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// Stepper do fluxo do pedido (design A12), igual para a cliente, o
/// responsável e o ajudante: cinco barras com o nome da fase por baixo. As
/// fases antes de [stage] ficam verde-escuro, a atual verde-claro e o nome
/// a negrito; as seguintes a cinzento.
class JobFlowStepper extends StatelessWidget {
  const JobFlowStepper({required this.stage, super.key});

  final JobFlowStage stage;

  static const double _barHeight = 5;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final current = stage.index;

    return Semantics(
      label:
          'Fase: ${stage.label}, ${current + 1} de '
          '${JobFlowStage.values.length}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.xxs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final step in JobFlowStage.values) ...[
              if (step.index > 0) const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: _barHeight,
                      decoration: BoxDecoration(
                        color: step.index < current
                            ? AppColors.primary
                            : step.index == current
                            ? AppColors.agendaHelperBar
                            : AppColors.divider,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      step.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        color: step.index <= current
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontWeight: step.index == current
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
