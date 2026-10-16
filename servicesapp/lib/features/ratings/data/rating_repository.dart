import 'package:supabase_flutter/supabase_flutter.dart';

import 'rating_model.dart';

class RatingRepository {
  const RatingRepository(this._client);
  final SupabaseClient _client;

  Future<Rating?> fetchMyRatingForJob(String jobId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final data = await _client
        .from('ratings')
        .select()
        .eq('job_id', jobId)
        .eq('rater_id', userId)
        .limit(1)
        .maybeSingle();
    return data == null ? null : Rating.fromJson(data);
  }

  Future<Rating?> fetchMyRatingForJobAndRatee({
    required String jobId,
    required String rateeId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final data = await _client
        .from('ratings')
        .select()
        .eq('job_id', jobId)
        .eq('rater_id', userId)
        .eq('ratee_id', rateeId)
        .maybeSingle();
    return data == null ? null : Rating.fromJson(data);
  }

  Future<void> submitClientRating({
    required String jobId,
    required int stars,
    String? comment,
  }) async {
    await _client.rpc('submit_client_rating', params: {
      'p_job_id': jobId,
      'p_stars': stars,
      'p_comment': comment,
    });
  }

  Future<void> submitPrincipalRating({
    required String jobId,
    required String rateeId,
    required int stars,
    String? comment,
  }) async {
    await _client.rpc('submit_principal_rating', params: {
      'p_job_id': jobId,
      'p_ratee_id': rateeId,
      'p_stars': stars,
      'p_comment': comment,
    });
  }

  Future<void> submitHelperRating({
    required String jobId,
    required int stars,
    String? comment,
  }) async {
    await _client.rpc('submit_helper_rating', params: {
      'p_job_id': jobId,
      'p_stars': stars,
      'p_comment': comment,
    });
  }

  Future<List<AcceptedHelper>> fetchAcceptedHelpersForJob(
      String jobId) async {
    final data = await _client.rpc(
      'get_accepted_helpers_for_job',
      params: {'p_job_id': jobId},
    );
    return (data as List)
        .map((e) => AcceptedHelper.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Rating>> fetchRatingsForProfile(String profileId) async {
    final data = await _client
        .from('ratings')
        .select()
        .eq('ratee_id', profileId)
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => Rating.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RatingSummary> fetchRatingSummary(String workerId) async {
    final data = await _client
        .from('worker_rating_summary')
        .select()
        .eq('worker_id', workerId)
        .maybeSingle();
    if (data == null) return (avgRating: 0.0, ratingCount: 0);
    return (
      avgRating: (data['avg_rating'] as num).toDouble(),
      ratingCount: (data['rating_count'] as num).toInt(),
    );
  }

  // RPC em vez de SELECT direto: `ratings` é pública (USING(true)), mas o
  // embedded join a `profiles` para o nome do rater não é — não existe
  // policy que cubra "quem vê este worker avaliado vê o perfil de quem o
  // avaliou". Antes do hardening de segurança (migration 0032) a policy
  // `profiles` era USING(true) e o join "funcionava" por acidente; hoje
  // devolve sempre null, mostrando "—" para praticamente todos os raters.
  // `get_ratings_with_rater_identity` (migration 0040, NÃO aplicada) expõe
  // só nome/avatar do rater, sem restrição adicional de autorização — a
  // mesma informação que `ratings` já é pública a qualquer autenticado.
  Future<List<Rating>> fetchRatingsWithRaterNames(String workerId) async {
    final data = await _client.rpc(
      'get_ratings_with_rater_identity',
      params: {'p_ratee_id': workerId},
    );
    return (data as List)
        .map((e) => Rating.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Avaliações recebidas pelo utilizador atual (`ratee_id = auth.uid()`),
  /// com nome/foto de quem avaliou e o serviço do job. RPC porque um
  /// ajudante não tem policy de SELECT em `job_requests` (só chega lá via
  /// RPCs SECURITY DEFINER) — ver cabeçalho da migration 0038.
  Future<List<RatingWithParty>> fetchMyRatingsReceived() async {
    final data = await _client.rpc('get_my_ratings_received');
    return (data as List)
        .map((e) => RatingWithParty.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Avaliações dadas pelo utilizador atual (`rater_id = auth.uid()`), com
  /// nome/foto de quem foi avaliado e o serviço do job.
  Future<List<RatingWithParty>> fetchMyRatingsGiven() async {
    final data = await _client.rpc('get_my_ratings_given');
    return (data as List)
        .map((e) => RatingWithParty.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
