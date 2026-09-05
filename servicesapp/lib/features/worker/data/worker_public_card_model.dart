/// Perfil público mínimo do worker — fonte: view `worker_public_card`
/// (migration 0033, definer-style, GRANT a `anon`). Sem telefone nem
/// localização exata.
class WorkerPublicCard {
  final String workerId;
  final String fullName;
  final String? avatarUrl;
  final String? bio;
  final String locationName;
  final List<String> serviceNames;
  final double avgRating;
  final int ratingCount;

  const WorkerPublicCard({
    required this.workerId,
    required this.fullName,
    this.avatarUrl,
    this.bio,
    required this.locationName,
    required this.serviceNames,
    required this.avgRating,
    required this.ratingCount,
  });

  factory WorkerPublicCard.fromJson(Map<String, dynamic> json) =>
      WorkerPublicCard(
        workerId: json['worker_id'] as String,
        fullName: json['full_name'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String?,
        bio: json['bio'] as String?,
        locationName: json['location_name'] as String? ?? '',
        serviceNames: List<String>.from(json['service_names'] as List? ?? []),
        avgRating: (json['avg_rating'] as num?)?.toDouble() ?? 0,
        ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
      );
}
