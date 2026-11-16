import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../auth/application/auth_providers.dart';
import '../data/admin_models.dart';
import '../data/admin_repository.dart';
import '../data/admin_support_models.dart';

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
final adminOverviewProvider = FutureProvider.autoDispose
    .family<AdminOverview, int?>((ref, days) {
      return ref.read(adminRepositoryProvider).fetchOverview(days: days);
    });

const adminWorkersPageSize = 30;

/// (pesquisa, plano, página a contar de 0).
typedef AdminWorkersQuery = ({String search, WorkerPlanTier? tier, int page});

final adminWorkersProvider = FutureProvider.autoDispose
    .family<List<AdminWorkerRow>, AdminWorkersQuery>((ref, query) {
      return ref
          .read(adminRepositoryProvider)
          .fetchWorkers(
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

// ── Suporte, fase A ───────────────────────────────────────────────

/// Resultados da pesquisa global. Texto com menos de 2 carateres não
/// chega à BD.
final adminSearchProvider = FutureProvider.autoDispose
    .family<List<AdminSearchHit>, String>((ref, query) {
      return ref.read(adminRepositoryProvider).search(query);
    });

const adminJobsPageSize = 30;

/// Filtros da lista de pedidos. Fica vivo enquanto o painel está aberto,
/// para não se perderem ao abrir e fechar fichas.
class AdminJobsFilterNotifier extends Notifier<AdminJobsFilter> {
  @override
  AdminJobsFilter build() => const AdminJobsFilter();

  void update(AdminJobsFilter filter) => state = filter;
}

final adminJobsFilterProvider =
    NotifierProvider<AdminJobsFilterNotifier, AdminJobsFilter>(
      AdminJobsFilterNotifier.new,
    );

final adminJobsProvider = FutureProvider.autoDispose
    .family<List<AdminJobRow>, AdminJobsFilter>((ref, filter) {
      return ref
          .read(adminRepositoryProvider)
          .fetchJobs(filter, limit: adminJobsPageSize);
    });

final adminJobDetailProvider = FutureProvider.autoDispose
    .family<AdminJobDetail, String>((ref, jobId) {
      return ref.read(adminRepositoryProvider).fetchJob(jobId);
    });

/// Só se pede quando se abre o separador Fotos (regista a consulta).
final adminJobPhotosProvider = FutureProvider.autoDispose
    .family<List<AdminJobPhoto>, String>((ref, jobId) {
      return ref.read(adminRepositoryProvider).fetchJobPhotos(jobId);
    });

const adminClientsPageSize = 30;

class AdminClientsFilterNotifier extends Notifier<AdminClientsFilter> {
  @override
  AdminClientsFilter build() => const AdminClientsFilter();

  void update(AdminClientsFilter filter) => state = filter;
}

final adminClientsFilterProvider =
    NotifierProvider<AdminClientsFilterNotifier, AdminClientsFilter>(
      AdminClientsFilterNotifier.new,
    );

final adminClientsProvider = FutureProvider.autoDispose
    .family<List<AdminClientRow>, AdminClientsFilter>((ref, filter) {
      return ref
          .read(adminRepositoryProvider)
          .fetchClients(filter, limit: adminClientsPageSize);
    });

final adminClientDetailProvider = FutureProvider.autoDispose
    .family<AdminClientDetail, String>((ref, clientId) {
      return ref.read(adminRepositoryProvider).fetchClient(clientId);
    });
