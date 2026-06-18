import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final jobPhotosProvider =
    FutureProvider.family<List<String>, String>((ref, jobId) {
  return ref.read(jobRepositoryProvider).fetchJobPhotos(jobId);
});

final jobByIdProvider =
    FutureProvider.family<JobRequest?, String>((ref, jobId) async {
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
