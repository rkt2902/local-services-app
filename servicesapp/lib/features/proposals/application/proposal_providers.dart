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

final workerProposalsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref
      .read(proposalRepositoryProvider)
      .fetchWorkerProposalsWithJobs(user.id);
});
