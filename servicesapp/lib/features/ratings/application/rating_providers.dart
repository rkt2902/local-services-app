import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/rating_model.dart';
import '../data/rating_repository.dart';

export '../data/rating_model.dart';
export '../data/rating_repository.dart';

/// Aggregated rating stats for a worker (avg + count), keyed by workerId.
final ratingSummaryProvider =
    FutureProvider.family<RatingSummary, String>((ref, workerId) {
  return ref.read(ratingRepositoryProvider).fetchRatingSummary(workerId);
});

/// All ratings for a worker with rater name joined, keyed by workerId.
final ratingsWithNamesProvider =
    FutureProvider.family<List<Rating>, String>((ref, workerId) {
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
final acceptedHelpersForJobProvider =
    FutureProvider.family<List<AcceptedHelper>, String>((ref, jobId) {
  return ref
      .read(ratingRepositoryProvider)
      .fetchAcceptedHelpersForJob(jobId);
});
