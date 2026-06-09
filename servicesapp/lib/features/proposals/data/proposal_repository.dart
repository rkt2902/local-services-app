import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/enums.dart';
import 'proposal_model.dart';

class ProposalRepository {
  const ProposalRepository(this._client);

  final SupabaseClient _client;

  Future<JobProposal?> fetchProposalForJob(String jobId) async {
    if (jobId.isEmpty) return null;
    final data = await _client
        .from('job_proposals')
        .select()
        .eq('job_id', jobId)
        .eq('status', ProposalStatus.pending.value)
        .maybeSingle();
    if (data == null) return null;
    return JobProposal.fromJson(data);
  }

  Future<JobProposal?> fetchProposalById(String proposalId) async {
    if (proposalId.isEmpty) return null;
    final data = await _client
        .from('job_proposals')
        .select()
        .eq('id', proposalId)
        .maybeSingle();
    if (data == null) return null;
    return JobProposal.fromJson(data);
  }

  Future<void> acceptProposal(String proposalId, String jobId) async {
    await _client
        .from('job_proposals')
        .update({
          'status': ProposalStatus.accepted.value,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', proposalId);
    await _client.from('job_requests').update({
      'status': JobStatus.confirmed.value,
      'accepted_proposal_id': proposalId,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', jobId);
  }

  Future<void> rejectProposal(String proposalId, String jobId) async {
    await _client
        .from('job_proposals')
        .update({
          'status': ProposalStatus.rejected.value,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', proposalId);
    await _client.from('job_requests').update({
      'status': JobStatus.open.value,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', jobId);
  }
}
