import 'package:flutter/material.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_support_sheet.dart';
import '../application/worker_plan_features.dart';
import '../application/worker_plan_labels.dart';
import '../data/worker_plan_model.dart';

/// Folha "Plano": o plano atual e a comparação dos três. Sem preços nem
/// forma de pagar (regras das lojas): mudar de plano é pelo suporte.
Future<void> showWorkerPlanSheet(BuildContext context, WorkerPlan plan) {
  return AppSheet.show<void>(
    context,
    builder: (sheetContext) => AppSheet(
      title: 'Plano ${plan.tier.label}',
      onClose: () => Navigator.of(sheetContext).pop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            workerPlanExplanation(plan),
            style: Theme.of(sheetContext)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          WorkerPlanComparison(
            current: plan.tier,
            freeMonthlyLimit: plan.tier.isPaid ? null : plan.monthlyJobLimit,
          ),
          if (plan.tier != WorkerPlanTier.proPlus) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                showSupportContactSheet(context);
              },
              icon: const Icon(Icons.support_agent_outlined),
              label: const Text('Mudar de plano'),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Tabela das funcionalidades por plano, com a coluna do plano atual em
/// destaque.
class WorkerPlanComparison extends StatelessWidget {
  const WorkerPlanComparison({
    super.key,
    required this.current,
    this.freeMonthlyLimit,
  });

  final WorkerPlanTier current;
  final int? freeMonthlyLimit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final rows = workerPlanFeatureRows(freeMonthlyLimit: freeMonthlyLimit);
    const tiers = WorkerPlanTier.values;

    Widget cell(String text, {required bool highlight, bool header = false}) {
      final included = text == planIncluded;
      return Expanded(
        flex: 2,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          color: highlight ? AppColors.primaryContainer : null,
          alignment: Alignment.center,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: (header ? textTheme.labelMedium : textTheme.bodySmall)?.copyWith(
              color: included || header || highlight
                  ? AppColors.primary
                  : AppColors.textSecondary,
              fontWeight: header || included ? FontWeight.w700 : null,
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(flex: 4, child: SizedBox.shrink()),
                for (final t in tiers)
                  cell(t.label, highlight: t == current, header: true),
              ],
            ),
            for (final row in rows) ...[
              const Divider(height: 1, color: AppColors.divider),
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.xs,
                      ),
                      child: Text(
                        row.label,
                        style: textTheme.bodySmall
                            ?.copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                  for (final t in tiers)
                    cell(row.valueFor(t), highlight: t == current),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
