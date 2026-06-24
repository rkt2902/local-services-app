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
    bool helpersEquipmentRequired = false,
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
      'p_helpers_equipment_required': helpersEquipmentRequired,
    };
    if (scheduledDate != null) {
      params['p_scheduled_date'] =
          scheduledDate.toIso8601String().substring(0, 10);
    }
    if (scheduledTime != null) {
      params['p_scheduled_time'] = scheduledTime;
    }
    try {
      final result = await _client.rpc('create_proposal', params: params);
      return result as String;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('já tens uma proposta') || msg.contains('p0001')) {
        throw Exception('Já enviaste uma proposta para este pedido.');
      }
      rethrow;
    }
  }

  Future<void> rejectProposal(String proposalId, String jobId) async {
    await _client.rpc('reject_proposal', params: {
      'p_proposal_id': proposalId,
      'p_job_id': jobId,
    });
  }

  Future<List<Map<String, dynamic>>> fetchPendingWorkerProposals(
      String workerId) async {
    final data = await _client
        .from('job_proposals')
        .select('*, job_requests!job_proposals_job_id_fkey(*)')
        .eq('worker_id', workerId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> fetchScheduledWorkerProposals(
      String workerId) async {
    final data = await _client
        .from('job_proposals')
        .select('*, job_requests!job_proposals_job_id_fkey(*)')
        .eq('worker_id', workerId)
        .eq('status', 'accepted')
        .order('created_at', ascending: false);

    return (data as List)
        .cast<Map<String, dynamic>>()
        .where((item) {
          final jobData = item['job_requests'] as Map<String, dynamic>?;
          if (jobData == null) return false;
          final jobStatus = jobData['status'] as String?;
          return jobStatus == 'confirmed' || jobStatus == 'awaiting_confirmation';
        })
        .toList()
      ..sort((a, b) {
          final aDate =
              (a['job_requests'] as Map?)?['confirmed_date'] as String?;
          final bDate =
              (b['job_requests'] as Map?)?['confirmed_date'] as String?;
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return aDate.compareTo(bDate);
        });
  }

  // TODO: Move completed filter to DB via RPC to avoid fetching non-completed
  // rows into the page range — client-side filter means pages may have fewer
  // items than pageSize even when more pages exist.
  Future<List<Map<String, dynamic>>> fetchCompletedWorkerProposals(
    String workerId, {
    int page = 0,
    int pageSize = 20,
  }) async {
    final data = await _client
        .from('job_proposals')
        .select('*, job_requests!job_proposals_job_id_fkey(*)')
        .eq('worker_id', workerId)
        .eq('status', 'accepted')
        .order('created_at', ascending: false)
        .range(page * pageSize, (page + 1) * pageSize - 1);

    return (data as List)
        .cast<Map<String, dynamic>>()
        .where((item) {
          final jobData = item['job_requests'] as Map<String, dynamic>?;
          if (jobData == null) return false;
          return jobData['status'] == 'completed';
        })
        .toList();
  }

  @Deprecated('Use fetchPendingWorkerProposals instead.')
  Future<List<Map<String, dynamic>>> fetchWorkerProposalsWithJobs(
      String workerId) async {
    return fetchPendingWorkerProposals(workerId);
  }

  Future<void> withdrawProposal(String proposalId, String jobId) async {
    await _client.rpc('withdraw_proposal', params: {
      'p_proposal_id': proposalId,
      'p_job_id': jobId,
    });
  }

  Future<void> markJobCompleted(String jobId) async {
    await _client.rpc('mark_job_done', params: {'p_job_id': jobId});
  }

  Future<void> confirmJobCompletion(String jobId) async {
    await _client
        .rpc('confirm_job_completion', params: {'p_job_id': jobId});
  }

  // REQUIRES: job_reports table with RLS policy allowing INSERT where
  // reporter_id = auth.uid(). Verify this exists in Supabase before relying
  // on this method — see docs/database_schema.md.
  Future<void> reportJobProblem({
    required String jobId,
    required String description,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Não autenticado');
    await _client.from('job_reports').insert({
      'job_id': jobId,
      'reporter_id': userId,
      'description': description,
    });
  }
}
