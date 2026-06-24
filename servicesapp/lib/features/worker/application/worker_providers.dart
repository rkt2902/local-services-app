import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../data/worker_repository.dart';
import '../data/worker_profile_model.dart';
import '../data/service_type_model.dart';

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
    FutureProvider.family<Map<String, String>, String>((ref, workerId) {
  return ref.read(workerRepositoryProvider).fetchWorkerBasicInfo(workerId);
});

final workerNameProvider =
    FutureProvider.family<String, String>((ref, workerId) {
  return ref.read(workerRepositoryProvider).fetchWorkerName(workerId);
});

final profileSummaryProvider =
    FutureProvider.family<Map<String, String?>, String>((ref, profileId) {
  return ref.read(workerRepositoryProvider).fetchProfileSummary(profileId);
});
