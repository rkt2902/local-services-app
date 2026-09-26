import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/provider_cache.dart';
import '../../auth/application/auth_providers.dart';
import '../../worker/application/worker_providers.dart' show workerProfileProvider;
import '../data/job_model.dart';
import '../data/job_repository.dart';

// serviceTypesProvider and ServiceType are reused from features/worker —
// see decisions_log.md (2026-06-08).
export '../../worker/application/worker_providers.dart'
    show serviceTypesProvider;
export '../../worker/data/service_type_model.dart' show ServiceType;

final jobRepositoryProvider = Provider<JobRepository>(
  (ref) => JobRepository(ref.watch(supabaseClientProvider)),
);

final clientJobsProvider = FutureProvider<List<JobRequest>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.read(jobRepositoryProvider).fetchClientJobs(user.id);
});

// Fotos são write-once (máx. 2, definidas na criação do job, sem UI de
// edição) — seguro reaproveitar por minutos.
const _jobPhotosCacheTtl = Duration(minutes: 5);

final jobPhotosProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, jobId) {
  cacheFor(ref, _jobPhotosCacheTtl);
  return ref.read(jobRepositoryProvider).fetchJobPhotos(jobId);
});

// Job muda com alguma frequência (nova proposta, remarcação, cancelamento)
// mas não precisa de estar fresco ao segundo — 45s cobre navegação
// lista↔detalhe sem servir dados muito desatualizados. Qualquer ação que
// muda o job já invalida explicitamente este provider (ver
// client_job_detail_screen.dart / worker_my_job_detail_screen.dart /
// notification_providers.dart) — a invalidação continua a ganhar sempre à
// janela de cache.
const _jobDetailCacheTtl = Duration(seconds: 45);

final jobByIdProvider =
    FutureProvider.autoDispose.family<JobRequest?, String>((ref, jobId) async {
  cacheFor(ref, _jobDetailCacheTtl);
  return ref.read(jobRepositoryProvider).fetchJobById(jobId);
});

final jobsInRadiusProvider = FutureProvider<List<JobRequest>>((ref) async {
  final workerProfile = await ref.watch(workerProfileProvider.future);
  if (workerProfile == null) return [];
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.read(jobRepositoryProvider).fetchJobsInRadius(
        workerLat: workerProfile.baseLat,
        workerLng: workerProfile.baseLng,
        radiusKm: workerProfile.radiusKm,
        workerId: user.id,
      );
});
