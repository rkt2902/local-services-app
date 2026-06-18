import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/proposal_model.dart';
import '../data/proposal_repository.dart';

final proposalRepositoryProvider = Provider<ProposalRepository>(
  (ref) => ProposalRepository(ref.watch(supabaseClientProvider)),
);

/// All pending proposals for a job — client sees this to choose one.
final pendingProposalsForJobProvider =
    FutureProvider.family<List<JobProposal>, String>((ref, jobId) {
  return ref
      .read(proposalRepositoryProvider)
      .fetchPendingProposalsForJob(jobId);
});

/// The accepted proposal for a confirmed job.
final acceptedProposalForJobProvider =
    FutureProvider.family<JobProposal?, String>((ref, jobId) {
  return ref
      .read(proposalRepositoryProvider)
      .fetchAcceptedProposalForJob(jobId);
});

final proposalByIdProvider =
    FutureProvider.family<JobProposal?, String>((ref, proposalId) {
  return ref.read(proposalRepositoryProvider).fetchProposalById(proposalId);
});

/// Check if a specific worker already has a pending proposal for a job.
final workerProposalForJobProvider =
    FutureProvider.family<JobProposal?, (String, String)>((ref, args) {
  return ref
      .read(proposalRepositoryProvider)
      .fetchWorkerProposalForJob(args.$1, args.$2);
});

/// Tab "Por confirmar" — proposals pending worker confirmation.
final pendingWorkerProposalsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref
      .read(proposalRepositoryProvider)
      .fetchPendingWorkerProposals(user.id);
});

/// Tab "Agendados" — accepted proposals with confirmed/awaiting_confirmation job.
final scheduledWorkerProposalsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref
      .read(proposalRepositoryProvider)
      .fetchScheduledWorkerProposals(user.id);
});

/// Tab "Concluídos" — paginated (20 per page). Watch page 0; load more imperatively.
final completedWorkerProposalsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, int>((ref, page) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref
      .read(proposalRepositoryProvider)
      .fetchCompletedWorkerProposals(user.id, page: page);
});

/// Backwards-compatible alias — delegates to pendingWorkerProposalsProvider.
final workerProposalsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(pendingWorkerProposalsProvider.future);
});

/// Invalidates all three worker proposal tab providers at once.
/// Use this instead of ref.invalidate(workerProposalsProvider) everywhere.
void invalidateAllWorkerProposalProviders(WidgetRef ref) {
  ref.invalidate(pendingWorkerProposalsProvider);
  ref.invalidate(scheduledWorkerProposalsProvider);
  ref.invalidate(completedWorkerProposalsProvider);
}
