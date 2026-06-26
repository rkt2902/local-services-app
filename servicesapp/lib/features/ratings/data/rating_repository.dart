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
}
