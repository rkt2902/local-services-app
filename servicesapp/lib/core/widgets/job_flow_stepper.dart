import 'package:flutter/material.dart';

import '../models/job_flow_stage.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// Stepper do fluxo do pedido (design A12), igual para a cliente, o
/// responsável e o ajudante: cinco barras com o nome da fase por baixo. As
/// fases antes de [stage] ficam verde-escuro, a atual verde-claro e o nome
/// a negrito; as seguintes a cinzento.
///
/// Sem ajudantes ([showTeam] falso) a fase Equipa não aparece: ficam
/// quatro barras (pedido do Henrique, 27/10).
class JobFlowStepper extends StatelessWidget {
  const JobFlowStepper({required this.stage, this.showTeam = true, super.key});

  final JobFlowStage stage;
  final bool showTeam;

  static const double _barHeight = 5;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final steps = [
      for (final s in JobFlowStage.values)
        if (showTeam || s != JobFlowStage.team) s,
    ];
    // Sem a fase Equipa, quem estava nela já está à espera do dia.
    final shown = !showTeam && stage == JobFlowStage.team
        ? JobFlowStage.onTheDay
        : stage;
    final current = steps.indexOf(shown);

    return Semantics(
      label: 'Fase: ${shown.label}, ${current + 1} de ${steps.length}',
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
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: _barHeight,
                      decoration: BoxDecoration(
                        color: i < current
                            ? AppColors.primary
                            : i == current
                            ? AppColors.agendaHelperBar
                            : AppColors.divider,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      steps[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        color: i <= current
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontWeight: i == current
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
