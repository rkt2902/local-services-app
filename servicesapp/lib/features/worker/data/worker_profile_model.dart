class WorkerProfile {
  final String profileId;
  final String fullName;
  final String phone;
  final String? avatarUrl;
  final String? bio;
  final double? defaultHourlyRate;
  final int radiusKm;
  final double baseLat;
  final double baseLng;
  final List<String> tools;
  final List<String> serviceTypeIds;

  const WorkerProfile({
    required this.profileId,
    required this.fullName,
    required this.phone,
    this.avatarUrl,
    this.bio,
    this.defaultHourlyRate,
    required this.radiusKm,
    required this.baseLat,
    required this.baseLng,
    required this.tools,
    required this.serviceTypeIds,
  });

  factory WorkerProfile.fromJson(
    Map<String, dynamic> json, {
    String fullName = '',
    String phone = '',
    String? avatarUrl,
    List<String> serviceTypeIds = const [],
  }) =>
      WorkerProfile(
        profileId: json['profile_id'] as String,
        fullName: fullName,
        phone: phone,
        avatarUrl: avatarUrl,
        bio: json['bio'] as String?,
        defaultHourlyRate: (json['default_hourly_rate'] as num?)?.toDouble(),
        radiusKm: (json['radius_km'] as num).toInt(),
        baseLat: (json['base_lat'] as num).toDouble(),
        baseLng: (json['base_lng'] as num).toDouble(),
        tools: List<String>.from(json['tools'] as List? ?? []),
        serviceTypeIds: serviceTypeIds,
      );

  Map<String, dynamic> toWorkerJson() => {
        'bio': bio,
        'default_hourly_rate': defaultHourlyRate,
        'radius_km': radiusKm,
        'base_lat': baseLat,
        'base_lng': baseLng,
        'tools': tools,
      };

  WorkerProfile copyWith({
    String? fullName,
    String? phone,
    String? avatarUrl,
    String? bio,
    double? defaultHourlyRate,
    int? radiusKm,
    double? baseLat,
    double? baseLng,
    List<String>? tools,
    List<String>? serviceTypeIds,
  }) =>
      WorkerProfile(
        profileId: profileId,
        fullName: fullName ?? this.fullName,
        phone: phone ?? this.phone,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        bio: bio ?? this.bio,
        defaultHourlyRate: defaultHourlyRate ?? this.defaultHourlyRate,
        radiusKm: radiusKm ?? this.radiusKm,
        baseLat: baseLat ?? this.baseLat,
        baseLng: baseLng ?? this.baseLng,
        tools: tools ?? this.tools,
        serviceTypeIds: serviceTypeIds ?? this.serviceTypeIds,
      );
}
