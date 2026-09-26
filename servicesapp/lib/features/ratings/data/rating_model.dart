class Rating {
  final String id;
  final String jobId;
  final String raterId;
  final String rateeId;
  final int stars;
  final String? comment;
  final DateTime createdAt;
  // Populated only when fetched via fetchRatingsWithRaterNames
  final String? raterName;

  const Rating({
    required this.id,
    required this.jobId,
    required this.raterId,
    required this.rateeId,
    required this.stars,
    this.comment,
    required this.createdAt,
    this.raterName,
  });

  factory Rating.fromJson(Map<String, dynamic> json) => Rating(
        id: json['id'] as String,
        jobId: json['job_id'] as String,
        raterId: json['rater_id'] as String,
        rateeId: json['ratee_id'] as String,
        stars: json['stars'] as int,
        comment: json['comment'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        raterName: (json['rater'] as Map<String, dynamic>?)?['full_name']
            as String?,
      );
}

typedef RatingSummary = ({double avgRating, int ratingCount});

/// A rating row joined with the *other* party in it and the job's service
/// type. `partyId`/`partyName`/`partyAvatarUrl` mean the rater when this
/// came from `get_my_ratings_received` (ratee = current user) and the ratee
/// when it came from `get_my_ratings_given` (rater = current user) — same
/// shape either way, so `my_ratings_screen.dart` doesn't need two models.
class RatingWithParty {
  final String id;
  final String jobId;
  final int stars;
  final String? comment;
  final DateTime createdAt;
  final String partyId;
  final String partyName;
  final String? partyAvatarUrl;
  final String? serviceTypeName;

  const RatingWithParty({
    required this.id,
    required this.jobId,
    required this.stars,
    this.comment,
    required this.createdAt,
    required this.partyId,
    required this.partyName,
    this.partyAvatarUrl,
    this.serviceTypeName,
  });

  factory RatingWithParty.fromJson(Map<String, dynamic> json) =>
      RatingWithParty(
        id: json['id'] as String,
        jobId: json['job_id'] as String,
        stars: json['stars'] as int,
        comment: json['comment'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        partyId: json['party_id'] as String,
        partyName: json['party_name'] as String? ?? '—',
        partyAvatarUrl: json['party_avatar_url'] as String?,
        serviceTypeName: json['service_type_name'] as String?,
      );
}

class AcceptedHelper {
  final String workerId;
  final String fullName;

  const AcceptedHelper({required this.workerId, required this.fullName});

  factory AcceptedHelper.fromJson(Map<String, dynamic> json) => AcceptedHelper(
        workerId: json['worker_id'] as String,
        fullName: json['full_name'] as String? ?? '—',
      );
}
