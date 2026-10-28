import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/provider_cache.dart';
import '../../auth/application/auth_providers.dart';
import '../data/worker_repository.dart';
import '../data/worker_profile_model.dart';
import '../data/worker_earnings_model.dart';
import '../data/worker_public_card_model.dart';
import '../data/worker_plan_model.dart';
import '../data/service_type_model.dart';

// Nome/telefone/avatar/bio mudam raramente (edição manual de perfil) —
// seguro reaproveitar por minutos em vez de refazer o fetch sempre que um
// ecrã diferente mostra o mesmo worker/cliente.
const _profileInfoCacheTtl = Duration(minutes: 5);

final workerRepositoryProvider = Provider<WorkerRepository>(
  (ref) => WorkerRepository(ref.watch(supabaseClientProvider)),
);

final workerProfileProvider = FutureProvider<WorkerProfile?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.read(workerRepositoryProvider).fetchProfile(user.id);
});

final workerHasProfileProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  return ref.read(workerRepositoryProvider).hasProfile(user.id);
});

final serviceTypesProvider = FutureProvider<List<ServiceType>>((ref) async {
  return ref.read(workerRepositoryProvider).fetchServiceTypes();
});

final workerBasicInfoProvider =
    FutureProvider.autoDispose.family<Map<String, String>, String>((ref, workerId) {
  cacheFor(ref, _profileInfoCacheTtl);
  return ref.read(workerRepositoryProvider).fetchWorkerBasicInfo(workerId);
});

/// Perfil público mínimo (cartão partilhável) — sem sessão necessária,
/// fonte: view `worker_public_card` (migration 0033).
final workerPublicCardProvider =
    FutureProvider.autoDispose.family<WorkerPublicCard?, String>((ref, workerId) {
  cacheFor(ref, _profileInfoCacheTtl);
  return ref.read(workerRepositoryProvider).fetchPublicCard(workerId);
});

/// Números do Perfil do jardineiro (0065). `null` sem a migration.
final myProfileStatsProvider = FutureProvider.autoDispose<
    ({int completedJobs, DateTime? memberSince})?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.read(workerRepositoryProvider).fetchMyProfileStats();
});

/// Plano do jardineiro com sessão e trabalhos aceites este mês (0060).
/// Invalidado quando uma proposta é aceite (ver notification_providers).
/// Ganhos dos últimos 12 meses (o mês atual incluído), para o painel de
/// ganhos. Só se pede com plano Pro ou Pro+ (o servidor recusa no Grátis).
final myEarningsProvider =
    FutureProvider.autoDispose<List<WorkerEarningEntry>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  final now = DateTime.now();
  return ref.read(workerRepositoryProvider).fetchMyEarnings(
        from: DateTime(now.year, now.month - 11),
        to: DateTime(now.year, now.month + 1, 0),
      );
});

final myWorkerPlanProvider = FutureProvider.autoDispose<WorkerPlan>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return WorkerPlan.unavailable;
  return ref.read(workerRepositoryProvider).fetchMyPlan();
});
