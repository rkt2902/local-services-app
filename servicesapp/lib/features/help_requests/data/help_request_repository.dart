import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/enums.dart';
import 'help_request_model.dart';

class HelpRequestRepository {
  const HelpRequestRepository(this._client);

  final SupabaseClient _client;

  Future<String> createHelpRequest({
    required String jobId,
    required String proposalId,
    required int slotsNeeded,
    required bool equipmentRequired,
    required bool createdPostConfirmation,
  }) async {
    final initialStatus = createdPostConfirmation
        ? HelpRequestStatus.pendingApproval.value
        : HelpRequestStatus.open.value;

    final result = await _client
        .from('help_requests')
        .insert({
          'job_id': jobId,
          'proposal_id': proposalId,
          'slots_needed': slotsNeeded,
          'equipment_required': equipmentRequired,
          'created_post_confirmation': createdPostConfirmation,
          'status': initialStatus,
        })
        .select('id')
        .single();

    return result['id'] as String;
  }

  Future<HelpRequest?> fetchHelpRequestById(String helpRequestId) async {
    if (helpRequestId.isEmpty) return null;
    final data = await _client
        .from('help_requests')
        .select()
        .eq('id', helpRequestId)
        .maybeSingle();
    if (data == null) return null;
    return HelpRequest.fromJson(data);
  }

  Future<List<HelpRequest>> fetchHelpRequestsForJob(String jobId) async {
    final data = await _client
        .from('help_requests')
        .select()
        .eq('job_id', jobId)
        .order('created_at', ascending: true);
    return (data as List).map((e) => HelpRequest.fromJson(e)).toList();
  }

  Future<List<HelpRequest>> fetchHelpRequestsInRadius({
    required double workerLat,
    required double workerLng,
    required int radiusKm,
  }) async {
    final data = await _client.rpc('get_help_requests_in_radius', params: {
      'worker_lat': workerLat,
      'worker_lng': workerLng,
      'radius_km': radiusKm,
    });
    return (data as List).map((e) => HelpRequest.fromJson(e)).toList();
  }

  Future<List<HelpRequestSummary>> fetchHelpRequestSummariesInRadius({
    required double workerLat,
    required double workerLng,
    required int radiusKm,
  }) async {
    final data = await _client.rpc('get_help_requests_in_radius', params: {
      'worker_lat': workerLat,
      'worker_lng': workerLng,
      'radius_km': radiusKm,
    });
    return (data as List).map((e) => HelpRequestSummary.fromJson(e)).toList();
  }

  // RPC (não um SELECT direto) porque não há nenhuma policy de `profiles`
  // que cubra "worker principal vê perfil de um candidato ajudante" — só
  // client↔worker com job confirmado. O embedded join antigo
  // (`profiles!help_acceptances_worker_id_fkey`) só "funcionava" enquanto
  // `profiles` tinha a policy pública USING(true), substituída pelo
  // hardening de segurança (migration 0032); desde então o join devolvia
  // sempre null para a contraparte. RPC `get_candidates_for_help_request`
  // (migration 0040, NÃO aplicada) reaproveita a mesma condição de
  // autorização da policy de SELECT já existente em `help_acceptances`
  // (`is_principal_worker_for_help_request`).
  Future<List<HelpAcceptance>> fetchCandidatesForHelpRequest(
      String helpRequestId) async {
    final data = await _client.rpc(
      'get_candidates_for_help_request',
      params: {'p_help_request_id': helpRequestId},
    );
    return (data as List).map((e) => HelpAcceptance.fromJson(e)).toList();
  }

  Future<void> applyToHelpRequest({
    required String helpRequestId,
    required bool broughtEquipment,
    String? message,
  }) async {
    final text = message?.trim();
    try {
      // 0048: RPC que também permite voltar a candidatar-se depois de uma
      // recusa ou desistência e avisa o jardineiro responsável.
      await _client.rpc('apply_to_help_request', params: {
        'p_help_request_id': helpRequestId,
        'p_brought_equipment': broughtEquipment,
        'p_message': (text == null || text.isEmpty) ? null : text,
      });
      return;
    } on PostgrestException catch (e) {
      // BD ainda sem a 0048 (função inexistente): caminho antigo.
      if (e.code != 'PGRST202') rethrow;
    }
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Não autenticado');
    await _client.from('help_acceptances').insert({
      'help_request_id': helpRequestId,
      'worker_id': userId,
      'status': 'pending',
      'brought_equipment': broughtEquipment,
      'agreed_rate': 0,
      if (message != null && message.isNotEmpty) 'message': message,
    });
  }

  Future<void> rejectHelpCandidate(String helpAcceptanceId) async {
    await _client.rpc('reject_help_candidate', params: {
      'p_help_acceptance_id': helpAcceptanceId,
    });
  }

  Future<void> acceptCandidate({
    required String helpAcceptanceId,
    required double agreedRate,
  }) async {
    await _client.rpc('accept_help_candidate', params: {
      'p_help_acceptance_id': helpAcceptanceId,
      'p_agreed_rate': agreedRate,
    });
  }

  Future<void> approveHelpRequest(String helpRequestId) async {
    await _client.rpc('approve_help_request', params: {
      'p_help_request_id': helpRequestId,
    });
  }

  Future<void> withdrawHelpAcceptance(String helpAcceptanceId) async {
    await _client.rpc('withdraw_help_acceptance', params: {
      'p_help_acceptance_id': helpAcceptanceId,
    });
  }

  Future<List<HelpAcceptanceSummary>> fetchMyHelpAcceptances() async {
    final data = await _client.rpc('get_my_help_acceptances');
    return (data as List)
        .map((e) => HelpAcceptanceSummary.fromJson(e))
        .toList();
  }
}
