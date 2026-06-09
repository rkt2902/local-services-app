import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/proposal_model.dart';
import '../data/proposal_repository.dart';

final proposalRepositoryProvider = Provider<ProposalRepository>(
  (ref) => ProposalRepository(ref.watch(supabaseClientProvider)),
);

final proposalForJobProvider =
    FutureProvider.family<JobProposal?, String>((ref, jobId) {
  return ref.read(proposalRepositoryProvider).fetchProposalForJob(jobId);
});

final proposalByIdProvider =
    FutureProvider.family<JobProposal?, String>((ref, proposalId) {
  return ref.read(proposalRepositoryProvider).fetchProposalById(proposalId);
});
