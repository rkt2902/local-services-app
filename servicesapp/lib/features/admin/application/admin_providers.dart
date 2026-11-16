import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../auth/application/auth_providers.dart';
import '../data/admin_account_models.dart';
import '../data/admin_growth_models.dart';
import '../data/admin_models.dart';
import '../data/admin_partner_models.dart';
import '../data/admin_repository.dart';
import '../data/admin_resolve_models.dart';
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

// ── Suporte, fase B ───────────────────────────────────────────────

const adminCasesPageSize = 30;

class AdminCasesFilterNotifier extends Notifier<AdminCasesFilter> {
  @override
  AdminCasesFilter build() => const AdminCasesFilter();

  void update(AdminCasesFilter filter) => state = filter;
}

final adminCasesFilterProvider =
    NotifierProvider<AdminCasesFilterNotifier, AdminCasesFilter>(
      AdminCasesFilterNotifier.new,
    );

final adminCasesProvider = FutureProvider.autoDispose
    .family<List<AdminCaseRow>, AdminCasesFilter>((ref, filter) {
      return ref
          .read(adminRepositoryProvider)
          .fetchCases(filter, limit: adminCasesPageSize);
    });

/// Casos ligados a uma pessoa ou a um pedido (fundo das fichas).
final adminCasesForTargetProvider = FutureProvider.autoDispose
    .family<List<AdminCaseRow>, String>((ref, targetId) {
      return ref
          .read(adminRepositoryProvider)
          .fetchCases(
            const AdminCasesFilter(status: 'all'),
            targetId: targetId,
            limit: 20,
          );
    });

final adminCaseDetailProvider = FutureProvider.autoDispose
    .family<AdminCaseDetail, String>((ref, caseId) {
      return ref.read(adminRepositoryProvider).fetchCase(caseId);
    });

const adminReportsPageSize = 30;

/// (estado: `null` = por tratar, `'all'` = todos; página).
typedef AdminReportsQuery = ({String? status, int page});

final adminReportsProvider = FutureProvider.autoDispose
    .family<List<AdminReportRow>, AdminReportsQuery>((ref, query) {
      return ref
          .read(adminRepositoryProvider)
          .fetchReports(
            status: query.status,
            limit: adminReportsPageSize,
            offset: query.page * adminReportsPageSize,
          );
    });

const adminRatingsPageSize = 30;

final adminRatingsProvider = FutureProvider.autoDispose
    .family<List<AdminModerationRating>, AdminRatingsQuery>((ref, query) {
      return ref
          .read(adminRepositoryProvider)
          .fetchRatings(query, limit: adminRatingsPageSize);
    });

final adminNotesProvider = FutureProvider.autoDispose
    .family<List<AdminNote>, String>((ref, targetId) {
      return ref.read(adminRepositoryProvider).fetchNotes(targetId);
    });

const adminActionsPageSize = 50;

final adminActionsProvider = FutureProvider.autoDispose
    .family<List<AdminActionRow>, AdminActionsQuery>((ref, query) {
      return ref
          .read(adminRepositoryProvider)
          .fetchActions(query, limit: adminActionsPageSize);
    });

// ── Suporte, fase C ───────────────────────────────────────────────

/// Estado da conta de uma pessoa (suspensa, encerramento, email, fotos).
final adminAccountProvider = FutureProvider.autoDispose
    .family<AdminAccountState, String>((ref, personId) {
      return ref.read(adminRepositoryProvider).fetchAccount(personId);
    });

/// Pontos do mapa; cada leitura fica no registo como consulta.
final adminMapPointsProvider = FutureProvider.autoDispose<List<AdminMapPoint>>(
  (ref) => ref.read(adminRepositoryProvider).fetchMapPoints(),
);

// ── Fase 3: funil, CSV, avisos ────────────────────────────────────

/// Funil do período em dias; `null` = desde sempre. Fica no Registo.
final adminFunnelProvider = FutureProvider.autoDispose
    .family<AdminFunnel, int?>((ref, days) {
      return ref.read(adminRepositoryProvider).fetchFunnel(days: days);
    });

/// Histórico dos avisos enviados (primeira página).
final adminNoticesProvider = FutureProvider.autoDispose<List<AdminNoticeRow>>(
  (ref) => ref.read(adminRepositoryProvider).fetchNotices(),
);

// ── Parceiros e zonas (0082) ──────────────────────────────────────

/// Cartões frota por estado (`null` = todos). Fica no Registo.
final adminFleetCardsProvider = FutureProvider.autoDispose
    .family<List<AdminFleetCardRow>, String?>((ref, status) {
      return ref.read(adminRepositoryProvider).fetchFleetCards(status: status);
    });

/// Gasolineiras parceiras, com jardineiros e pedidos perto.
final adminPartnersProvider =
    FutureProvider.autoDispose<List<AdminPartnerLocation>>(
      (ref) => ref.read(adminRepositoryProvider).fetchPartners(),
    );

/// Zonas do mapa (quadrados de 10 km, 90 dias).
final adminMapZonesProvider = FutureProvider.autoDispose<List<AdminMapZone>>(
  (ref) => ref.read(adminRepositoryProvider).fetchMapZones(),
);
