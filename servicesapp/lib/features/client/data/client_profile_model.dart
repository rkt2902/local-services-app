class ClientProfile {
  final String id;
  final String fullName;
  final String phone;
  final String? avatarUrl;
  final DateTime? createdAt;

  const ClientProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    this.avatarUrl,
    this.createdAt,
  });

  factory ClientProfile.fromJson(Map<String, dynamic> json) => ClientProfile(
        id: json['id'] as String,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String?,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'full_name': fullName,
        'phone': phone,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      };

  ClientProfile copyWith({String? fullName, String? phone, String? avatarUrl}) =>
      ClientProfile(
        id: id,
        fullName: fullName ?? this.fullName,
        phone: phone ?? this.phone,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        createdAt: createdAt,
      );
}
