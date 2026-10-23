import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../auth/application/auth_providers.dart';
import '../data/admin_models.dart';
import '../data/admin_repository.dart';

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(supabaseClientProvider)),
);

/// `null` sem sessão. Invalidar depois de confirmar o código da app
/// autenticadora (a sessão passa a aal2 mas o utilizador é o mesmo).
final adminAccessProvider = FutureProvider.autoDispose<AdminAccess?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.read(adminRepositoryProvider).fetchAccess();
});

/// Período da visão geral em dias; `null` = desde sempre.
final adminOverviewProvider =
    FutureProvider.autoDispose.family<AdminOverview, int?>((ref, days) {
  return ref.read(adminRepositoryProvider).fetchOverview(days: days);
});

const adminWorkersPageSize = 30;

/// (pesquisa, plano, página a contar de 0).
typedef AdminWorkersQuery = ({String search, WorkerPlanTier? tier, int page});

final adminWorkersProvider = FutureProvider.autoDispose
    .family<List<AdminWorkerRow>, AdminWorkersQuery>((ref, query) {
  return ref.read(adminRepositoryProvider).fetchWorkers(
        search: query.search,
        tier: query.tier,
        limit: adminWorkersPageSize,
        offset: query.page * adminWorkersPageSize,
      );
});

final adminWorkerDetailProvider = FutureProvider.autoDispose
    .family<AdminWorkerDetail, String>((ref, workerId) {
  return ref.read(adminRepositoryProvider).fetchWorker(workerId);
});
