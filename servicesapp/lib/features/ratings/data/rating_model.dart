class Rating {
  final String id;
  final String jobId;
  final String raterId;
  final String rateeId;
  final int stars;
  final String? comment;
  final DateTime createdAt;

  const Rating({
    required this.id,
    required this.jobId,
    required this.raterId,
    required this.rateeId,
    required this.stars,
    this.comment,
    required this.createdAt,
  });

  factory Rating.fromJson(Map<String, dynamic> json) => Rating(
        id: json['id'] as String,
        jobId: json['job_id'] as String,
        raterId: json['rater_id'] as String,
        rateeId: json['ratee_id'] as String,
        stars: json['stars'] as int,
        comment: json['comment'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
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
