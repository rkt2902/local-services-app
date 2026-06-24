import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../worker/application/worker_providers.dart' show workerProfileProvider;
import '../data/help_request_model.dart';
import '../data/help_request_repository.dart';

final helpRequestRepositoryProvider = Provider<HelpRequestRepository>(
  (ref) => HelpRequestRepository(ref.watch(supabaseClientProvider)),
);

final helpRequestsForJobProvider =
    FutureProvider.family<List<HelpRequest>, String>((ref, jobId) {
  return ref
      .read(helpRequestRepositoryProvider)
      .fetchHelpRequestsForJob(jobId);
});

final candidatesForHelpRequestProvider =
    FutureProvider.family<List<HelpAcceptance>, String>((ref, helpRequestId) {
  return ref
      .read(helpRequestRepositoryProvider)
      .fetchCandidatesForHelpRequest(helpRequestId);
});

final helpRequestsInRadiusProvider =
    FutureProvider<List<HelpRequest>>((ref) async {
  final workerProfile = await ref.watch(workerProfileProvider.future);
  if (workerProfile == null) return [];
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.read(helpRequestRepositoryProvider).fetchHelpRequestsInRadius(
        workerLat: workerProfile.baseLat,
        workerLng: workerProfile.baseLng,
        radiusKm: workerProfile.radiusKm,
      );
});

final helpRequestSummariesInRadiusProvider =
    FutureProvider<List<HelpRequestSummary>>((ref) async {
  final workerProfile = await ref.watch(workerProfileProvider.future);
  if (workerProfile == null) return [];
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref
      .read(helpRequestRepositoryProvider)
      .fetchHelpRequestSummariesInRadius(
        workerLat: workerProfile.baseLat,
        workerLng: workerProfile.baseLng,
        radiusKm: workerProfile.radiusKm,
      );
});
