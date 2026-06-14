import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/enums.dart';
import 'proposal_model.dart';

class ProposalRepository {
  const ProposalRepository(this._client);

  final SupabaseClient _client;

  Future<JobProposal?> fetchAcceptedProposalForJob(String jobId) async {
    if (jobId.isEmpty) return null;
    final data = await _client
        .from('job_proposals')
        .select()
        .eq('job_id', jobId)
        .eq('status', ProposalStatus.accepted.value)
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

  // RLS: relies on "Client vê propostas dos seus jobs" SELECT policy.
  // Policy must cover multi-row SELECT (not just maybeSingle).
  // Verify in Supabase: SELECT on job_proposals WHERE job_id IN
  // (SELECT id FROM job_requests WHERE client_id = auth.uid()).
  Future<List<JobProposal>> fetchPendingProposalsForJob(String jobId) async {
    if (jobId.isEmpty) return [];
    final data = await _client
        .from('job_proposals')
        .select()
        .eq('job_id', jobId)
        .eq('status', ProposalStatus.pending.value)
        .order('created_at', ascending: true);
    return (data as List).map((e) => JobProposal.fromJson(e)).toList();
  }

  Future<JobProposal?> fetchWorkerProposalForJob(
      String jobId, String workerId) async {
    if (jobId.isEmpty || workerId.isEmpty) return null;
    final data = await _client
        .from('job_proposals')
        .select()
        .eq('job_id', jobId)
        .eq('worker_id', workerId)
        .eq('status', ProposalStatus.pending.value)
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
    DateTime? scheduledDate,
    String? scheduledTime,
    bool scheduledFlexible = false,
  }) async {
    final params = <String, dynamic>{
      'p_job_id': jobId,
      'p_worker_id': workerId,
      'p_hourly_rate': hourlyRate,
      'p_estimated_hours_min': estimatedHoursMin,
      'p_estimated_hours_max': estimatedHoursMax,
      'p_people_needed': peopleNeeded,
      'p_notes': notes,
      'p_scheduled_flexible': scheduledFlexible,
    };
    if (scheduledDate != null) {
      params['p_scheduled_date'] =
          scheduledDate.toIso8601String().substring(0, 10);
    }
    if (scheduledTime != null) {
      params['p_scheduled_time'] = scheduledTime;
    }
    final result = await _client.rpc('create_proposal', params: params);
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
    await _client.rpc('withdraw_proposal', params: {
      'p_proposal_id': proposalId,
      'p_job_id': jobId,
    });
  }

  Future<void> markJobCompleted(String jobId) async {
    await _client.from('job_requests').update({
      'status': JobStatus.awaitingConfirmation.value,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', jobId);
  }
}
