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

  // RPC em vez de SELECT direto: a policy de SELECT de `job_proposals`
  // ("Client vê propostas dos seus jobs") cobre a linha da proposta, mas o
  // embedded join a `profiles` para nome/avatar do worker é bloqueado pela
  // policy de `profiles` — essa só deixa o cliente ler o perfil do worker
  // quando já existe proposta `accepted` (job confirmado), nunca para
  // propostas ainda `pending`. Antes do hardening de segurança (migration
  // 0032) `profiles` tinha USING(true) e o join "funcionava" por acidente;
  // hoje devolve sempre null aqui — exatamente onde o cliente mais precisa
  // de ver quem propôs, antes de decidir. `get_pending_proposals_for_job`
  // (migration 0040, NÃO aplicada) expõe só nome/avatar do worker, com a
  // mesma condição de autorização da policy ("job pertence a auth.uid()").
  Future<List<JobProposal>> fetchPendingProposalsForJob(String jobId) async {
    if (jobId.isEmpty) return [];
    final data = await _client.rpc(
      'get_pending_proposals_for_job',
      params: {'p_job_id': jobId},
    );
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

  /// Preço por hora: [hourlyRate]. Valor total ([pricingMode] fixedTotal):
  /// [totalPrice], e a BD guarda uma hora de referência (migration 0058).
  /// Os campos do A6 só vão quando têm valor, para a app continuar a
  /// enviar propostas por hora antes da 0058 aplicada.
  Future<String> createProposal({
    required String jobId,
    ProposalPricingMode pricingMode = ProposalPricingMode.hourly,
    double? hourlyRate,
    double? totalPrice,
    double? estimatedHoursMin,
    double? estimatedHoursMax,
    int? estimatedDaysMin,
    int? estimatedDaysMax,
    required int peopleNeeded,
    String? notes,
    List<String> includes = const [],
    DateTime? validUntil,
    DateTime? scheduledDate,
    String? scheduledTime,
    bool scheduledFlexible = false,
    bool helpersEquipmentRequired = false,
  }) async {
    final fixed = pricingMode == ProposalPricingMode.fixedTotal;
    final params = <String, dynamic>{
      'p_job_id': jobId,
      if (!fixed) 'p_hourly_rate': hourlyRate,
      'p_estimated_hours_min': estimatedHoursMin,
      'p_estimated_hours_max': estimatedHoursMax,
      'p_people_needed': peopleNeeded,
      'p_notes': notes,
      'p_scheduled_flexible': scheduledFlexible,
      'p_helpers_equipment_required': helpersEquipmentRequired,
      if (fixed) 'p_pricing_mode': pricingMode.value,
      if (fixed) 'p_total_price': totalPrice,
      if (includes.isNotEmpty) 'p_includes': includes,
      'p_estimated_days_min': ?estimatedDaysMin,
      'p_estimated_days_max': ?estimatedDaysMax,
      if (validUntil != null)
        'p_valid_until': validUntil.toIso8601String().substring(0, 10),
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

  /// Último formato de preço que o jardineiro usou ("Escolhemos o valor
  /// total porque o usaste da última vez"). Antes da 0058 ou sem
  /// propostas devolve null.
  Future<ProposalPricingMode?> fetchLastPricingMode(String workerId) async {
    try {
      final data = await _client
          .from('job_proposals')
          .select('pricing_mode')
          .eq('worker_id', workerId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data == null) return null;
      return ProposalPricingMode.fromString(data['pricing_mode'] as String?);
    } catch (_) {
      return null;
    }
  }

  /// Opções de "O que inclui" ativas, por ordem (migration 0058).
  Future<List<ProposalIncludeOption>> fetchIncludeOptions() async {
    final data = await _client
        .from('proposal_include_options')
        .select('slug, label')
        .eq('active', true)
        .order('sort_order');
    return (data as List)
        .map((e) => ProposalIncludeOption.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Dias de trabalho de um trabalho iniciado (migration 0058).
  Future<List<JobWorkDay>> fetchWorkDays(String jobId) async {
    final data =
        await _client.rpc('get_job_work_days', params: {'p_job_id': jobId});
    return (data as List)
        .map((e) => JobWorkDay.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// "Terminar o dia N".
  Future<void> finishWorkDay(String jobId) async {
    await _client.rpc('finish_work_day', params: {'p_job_id': jobId});
  }

  /// "Começar o dia N+1".
  Future<void> startWorkDay(String jobId) async {
    await _client.rpc('start_work_day', params: {'p_job_id': jobId});
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
        // `!inner`: sem ele o filtro sobre a tabela embebida só esvazia o
        // `job_requests` embebido (fica null) em vez de excluir a proposta,
        // e voltavam todas as propostas aceites de sempre (cancelados e
        // concluídos incluídos).
        .select('*, job_requests!job_proposals_job_id_fkey!inner(*)')
        .eq('worker_id', workerId)
        .eq('status', 'accepted')
        .filter('job_requests.status', 'in', '(confirmed,awaiting_confirmation)')
        .order('created_at', ascending: false);

    return (data as List).cast<Map<String, dynamic>>().toList()
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

  Future<List<Map<String, dynamic>>> fetchCompletedWorkerProposals(
    String workerId, {
    int page = 0,
    int pageSize = 20,
  }) async {
    final data = await _client
        .from('job_proposals')
        // `!inner` pelo mesmo motivo que em fetchScheduledWorkerProposals.
        .select('*, job_requests!job_proposals_job_id_fkey!inner(*)')
        .eq('worker_id', workerId)
        .eq('status', 'accepted')
        .filter('job_requests.status', 'eq', 'completed')
        .order('created_at', ascending: false)
        .range(page * pageSize, (page + 1) * pageSize - 1);
    return (data as List).cast<Map<String, dynamic>>().toList();
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

  /// [photoPath] é o caminho devolvido por
  /// `JobRepository.uploadCompletionPhoto` (opcional). A RPC recusa antes
  /// do dia do trabalho (migration 0046).
  /// Exige o trabalho iniciado; até 3 fotos de "depois" (migration 0052).
  Future<void> markJobCompleted(
    String jobId, {
    List<String> photoPaths = const [],
  }) async {
    await _client.rpc('mark_job_done', params: {
      'p_job_id': jobId,
      'p_photo_paths': photoPaths,
    });
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
