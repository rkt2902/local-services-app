class AppNotification {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final String? relatedId;
  final String? relatedType;
  final bool read;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.relatedId,
    this.relatedType,
    required this.read,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        type: json['type'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        relatedId: json['related_id'] as String?,
        relatedType: json['related_type'] as String?,
        read: json['read'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        userId: userId,
        type: type,
        title: title,
        body: body,
        relatedId: relatedId,
        relatedType: relatedType,
        read: read ?? this.read,
        createdAt: createdAt,
      );
}
