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
    await _client.rpc('accept_proposal', params: {
      'p_proposal_id': proposalId,
      'p_job_id': jobId,
    });
  }


  Future<String> createProposal({
    required String jobId,
    required String workerId,
    required double hourlyRate,
    double? estimatedHoursMin,
    double? estimatedHoursMax,
    required int peopleNeeded,
    String? notes,
  }) async {
    final result = await _client.rpc('create_proposal', params: {
      'p_job_id': jobId,
      'p_worker_id': workerId,
      'p_hourly_rate': hourlyRate,
      'p_estimated_hours_min': estimatedHoursMin,
      'p_estimated_hours_max': estimatedHoursMax,
      'p_people_needed': peopleNeeded,
      'p_notes': notes,
    });
    return result as String;
  }

  Future<void> rejectProposal(String proposalId, String jobId) async {
    await _client.rpc('reject_proposal', params: {
      'p_proposal_id': proposalId,
      'p_job_id': jobId,
    });
  }

  Future<List<Map<String, dynamic>>> fetchWorkerProposalsWithJobs(
      String workerId) async {
    final data = await _client
        .from('job_proposals')
        .select('*, job_requests!job_proposals_job_id_fkey(*)')
        .eq('worker_id', workerId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> withdrawProposal(String proposalId, String jobId) async {
    await _client
        .from('job_proposals')
        .update({
          'status': ProposalStatus.superseded.value,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', proposalId);
    await _client.from('job_requests').update({
      'status': JobStatus.open.value,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', jobId);
  }

  Future<void> markJobCompleted(String jobId) async {
    await _client.from('job_requests').update({
      'status': JobStatus.completed.value,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', jobId);
  }
}
