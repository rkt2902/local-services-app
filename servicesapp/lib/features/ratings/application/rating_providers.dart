import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/provider_cache.dart';
import '../../auth/application/auth_providers.dart';
import '../data/rating_model.dart';
import '../data/rating_repository.dart';

export '../data/rating_model.dart';
export '../data/rating_repository.dart';

// Média/contagem de estrelas e a lista de avaliações mudam raramente
// (só quando um novo job é avaliado) — seguro reaproveitar por minutos.
// Nota: hoje nenhum destes dois providers é invalidado depois de
// submitClientRating/submitPrincipalRating/submitHelperRating (gap
// pré-existente, não introduzido por esta mudança — sem a cache o dado já
// ficava desatualizado indefinidamente até restart da app).
const _ratingsCacheTtl = Duration(minutes: 5);

/// Aggregated rating stats for a worker (avg + count), keyed by workerId.
final ratingSummaryProvider =
    FutureProvider.autoDispose.family<RatingSummary, String>((ref, workerId) {
  cacheFor(ref, _ratingsCacheTtl);
  return ref.read(ratingRepositoryProvider).fetchRatingSummary(workerId);
});

/// All ratings for a worker with rater name joined, keyed by workerId.
final ratingsWithNamesProvider =
    FutureProvider.autoDispose.family<List<Rating>, String>((ref, workerId) {
  cacheFor(ref, _ratingsCacheTtl);
  return ref
      .read(ratingRepositoryProvider)
      .fetchRatingsWithRaterNames(workerId);
});

final ratingRepositoryProvider = Provider<RatingRepository>(
  (ref) => RatingRepository(ref.watch(supabaseClientProvider)),
);

/// Returns the first rating row where the current user is the rater for [jobId].
/// Sufficient for single-action raters (client, helper) where at most one
/// rating action exists per job.
final myRatingForJobProvider =
    FutureProvider.family<Rating?, String>((ref, jobId) {
  return ref.read(ratingRepositoryProvider).fetchMyRatingForJob(jobId);
});

/// Returns the rating row for a specific (jobId, rateeId) pair from the
/// current user. Used by the principal, who rates each participant separately.
final myRatingForJobAndRateeProvider =
    FutureProvider.family<Rating?, (String, String)>((ref, args) {
  final (jobId, rateeId) = args;
  return ref
      .read(ratingRepositoryProvider)
      .fetchMyRatingForJobAndRatee(jobId: jobId, rateeId: rateeId);
});

/// Lists the accepted helpers for a job, keyed by jobId.
/// Only succeeds when the current user is the principal of that job.
/// Mesma janela que jobByIdProvider — a composição da equipa muda ao
/// ritmo do próprio job, não ao segundo.
const _acceptedHelpersCacheTtl = Duration(seconds: 45);

final acceptedHelpersForJobProvider =
    FutureProvider.autoDispose.family<List<AcceptedHelper>, String>((ref, jobId) {
  cacheFor(ref, _acceptedHelpersCacheTtl);
  return ref
      .read(ratingRepositoryProvider)
      .fetchAcceptedHelpersForJob(jobId);
});

/// Avaliações recebidas pelo utilizador atual — tab "Recebidas" de
/// "As minhas avaliações". Igual para cliente e worker.
final myRatingsReceivedProvider =
    FutureProvider.autoDispose<List<RatingWithParty>>((ref) {
  cacheFor(ref, _ratingsCacheTtl);
  return ref.read(ratingRepositoryProvider).fetchMyRatingsReceived();
});

/// Avaliações dadas pelo utilizador atual — tab "Dadas" de
/// "As minhas avaliações". Igual para cliente e worker.
final myRatingsGivenProvider =
    FutureProvider.autoDispose<List<RatingWithParty>>((ref) {
  cacheFor(ref, _ratingsCacheTtl);
  return ref.read(ratingRepositoryProvider).fetchMyRatingsGiven();
});
