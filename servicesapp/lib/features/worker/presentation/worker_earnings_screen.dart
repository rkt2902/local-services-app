import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/router/app_back_navigation.dart';
import '../application/worker_earnings.dart';
import '../application/worker_plan_features.dart';
import '../application/worker_providers.dart';
import 'widgets/worker_earnings_view.dart';
import 'worker_plan_sheet.dart';

/// `/worker/earnings`: liga o plano e `get_my_earnings` (0067) à vista
/// pura. No Grátis não pede nada ao servidor, mostra só o convite.
class WorkerEarningsScreen extends ConsumerWidget {
  const WorkerEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(myWorkerPlanProvider);
    final plan = planAsync.asData?.value;
    final tier = plan?.tier ?? WorkerPlanTier.free;
    final locked = plan != null && !tier.hasEarnings;

    final AsyncValue<List<WorkerEarningsMonth>> monthsAsync;
    if (plan == null) {
      monthsAsync = planAsync.hasError
          ? AsyncValue.error(planAsync.error!, planAsync.stackTrace!)
          : const AsyncValue.loading();
    } else if (locked) {
      monthsAsync = const AsyncValue.data([]);
    } else {
      monthsAsync = ref.watch(myEarningsProvider).whenData(
            (entries) => groupEarningsByMonth(
              entries,
              lastMonth: DateTime.now(),
              months: 12,
            ),
          );
    }

    return WorkerEarningsView(
      locked: locked,
      monthsAsync: monthsAsync,
      onBack: () => goBackOrToRoleHome(context),
      onOpenPlans: () {
        if (plan != null) showWorkerPlanSheet(context, plan);
      },
      onRetry: () {
        ref.invalidate(myWorkerPlanProvider);
        ref.invalidate(myEarningsProvider);
      },
      onRefresh: () async {
        ref.invalidate(myEarningsProvider);
        await ref.read(myEarningsProvider.future);
      },
    );
  }
}
