import 'worker_showcase.dart';

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
  final String locationName;
  final List<String> tools;
  final List<String> serviceTypeIds;

  /// Destaques e links do perfil (0051). Só são gravados quando a linha
  /// lida da BD já tinha estas colunas ([showcaseSupported]): assim a app
  /// nova continua a gravar o resto do perfil antes de a 0051 ser aplicada.
  final List<String> highlights;
  final List<WorkerSocialLink> socialLinks;
  final bool showcaseSupported;

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
    this.locationName = '',
    required this.tools,
    required this.serviceTypeIds,
    this.highlights = const [],
    this.socialLinks = const [],
    this.showcaseSupported = false,
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
        locationName: json['location_name'] as String? ?? '',
        tools: List<String>.from(json['tools'] as List? ?? []),
        serviceTypeIds: serviceTypeIds,
        highlights: highlightsFromJson(json['highlights']),
        socialLinks: WorkerSocialLink.listFromJson(json['social_links']),
        showcaseSupported: json.containsKey('highlights') &&
            json.containsKey('social_links'),
      );

  Map<String, dynamic> toWorkerJson() => {
        'bio': bio,
        'default_hourly_rate': defaultHourlyRate,
        'radius_km': radiusKm,
        'base_lat': baseLat,
        'base_lng': baseLng,
        'tools': tools,
        if (locationName.isNotEmpty) 'location_name': locationName,
        if (showcaseSupported) ...{
          'highlights': highlights,
          'social_links': socialLinks.map((l) => l.toJson()).toList(),
        },
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
    String? locationName,
    List<String>? tools,
    List<String>? serviceTypeIds,
    List<String>? highlights,
    List<WorkerSocialLink>? socialLinks,
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
        locationName: locationName ?? this.locationName,
        tools: tools ?? this.tools,
        serviceTypeIds: serviceTypeIds ?? this.serviceTypeIds,
        highlights: highlights ?? this.highlights,
        socialLinks: socialLinks ?? this.socialLinks,
        showcaseSupported: showcaseSupported,
      );
}
