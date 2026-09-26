import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../auth/application/auth_providers.dart';
import '../application/rating_providers.dart';
import 'my_ratings_screen.dart';

final _dateFormat = DateFormat('dd/MM/yyyy');

/// MVP só tem a categoria "Jardinagem" — ícone genérico único, mesma
/// decisão já tomada em `ClientServiceTypeTile`/`worker_available_jobs_screen`.
const _serviceIcon = Icons.yard_outlined;

/// Wrapper de "As minhas avaliações" — resolve os providers e traduz para
/// ViewData do `MyRatingsScreen` genérico. Vive em `ratings/` (não em
/// `worker/` nem `client/`) porque não tem NENHUM código específico de
/// papel: `get_my_ratings_received`/`get_my_ratings_given` filtram sempre
/// por `auth.uid()`, e `ratingSummaryProvider` (a view `worker_rating_summary`,
/// que agrega por `ratee_id` sem filtro de papel) já serve os dois lados —
/// por isso as rotas `/worker/ratings` e `/client/ratings` usam esta mesma
/// classe em vez de duas cópias quase idênticas.
class MyRatingsRoute extends ConsumerWidget {
  const MyRatingsRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserProvider)?.id;
    final summaryAsync = userId == null
        ? const AsyncValue<RatingSummary>.loading()
        : ref.watch(ratingSummaryProvider(userId));
    final receivedAsync = ref.watch(myRatingsReceivedProvider);
    final givenAsync = ref.watch(myRatingsGivenProvider);

    final receivedTabLabel = receivedAsync.maybeWhen(
      data: (list) => 'Recebidas ${list.length}',
      orElse: () => 'Recebidas',
    );
    final givenTabLabel = givenAsync.maybeWhen(
      data: (list) => 'Dadas ${list.length}',
      orElse: () => 'Dadas',
    );

    return MyRatingsScreen(
      summaryAsync: summaryAsync.whenData(_summaryViewData),
      receivedAsync: receivedAsync.whenData(
        (list) => list.map(_receivedViewData).toList(),
      ),
      givenAsync: givenAsync.whenData(
        (list) => list.map(_givenViewData).toList(),
      ),
      receivedTabLabel: receivedTabLabel,
      givenTabLabel: givenTabLabel,
      onBack: () => context.pop(),
      onRetrySummary: userId == null
          ? null
          : () => ref.invalidate(ratingSummaryProvider(userId)),
      onRetryReceived: () => ref.invalidate(myRatingsReceivedProvider),
      onRetryGiven: () => ref.invalidate(myRatingsGivenProvider),
    );
  }
}

MyRatingsSummaryViewData _summaryViewData(RatingSummary summary) {
  return MyRatingsSummaryViewData(
    averageRatingLabel:
        summary.ratingCount == 0 ? '—' : summary.avgRating.toStringAsFixed(1),
    receivedReviewsLabel: '${summary.ratingCount} avaliações',
    filledSummaryStars: summary.avgRating.round(),
    maxSummaryStars: 5,
    hasReceivedReviews: summary.ratingCount > 0,
  );
}

ReceivedRatingViewData _receivedViewData(RatingWithParty rating) {
  return ReceivedRatingViewData(
    ratingId: rating.id,
    raterName: rating.partyName,
    raterAvatarUrl: rating.partyAvatarUrl,
    dateLabel: _dateFormat.format(rating.createdAt),
    filledStars: rating.stars,
    maxStars: 5,
    comment: rating.comment,
    serviceLabel: rating.serviceTypeName ?? 'Serviço',
    serviceIcon: _serviceIcon,
  );
}

GivenRatingViewData _givenViewData(RatingWithParty rating) {
  return GivenRatingViewData(
    ratingId: rating.id,
    rateeName: rating.partyName,
    rateeAvatarUrl: rating.partyAvatarUrl,
    dateLabel: _dateFormat.format(rating.createdAt),
    filledStars: rating.stars,
    maxStars: 5,
    comment: rating.comment,
    serviceLabel: rating.serviceTypeName ?? 'Serviço',
    serviceIcon: _serviceIcon,
  );
}
