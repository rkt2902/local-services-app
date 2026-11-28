import 'admin_invite_templates.dart';

/// Estado de um envio em `admin_invites` (0085).
enum AdminInviteStatus {
  pending('pending', 'A enviar'),
  sent('sent', 'Enviado'),
  failed('failed', 'Falhou');

  const AdminInviteStatus(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static AdminInviteStatus fromDb(String? value) => switch (value) {
    'sent' => sent,
    'failed' => failed,
    _ => pending,
  };
}

/// O que a BD sabe de um email antes de enviar (`admin_invite_status`).
class AdminInviteEmailInfo {
  const AdminInviteEmailInfo({
    required this.optedOut,
    required this.sentCount,
    required this.sentToday,
    required this.dailyLimit,
    this.optedOutAt,
    this.lastSentAt,
    this.lastTemplate,
  });

  final bool optedOut;
  final DateTime? optedOutAt;
  final int sentCount;
  final DateTime? lastSentAt;
  final AdminInviteTemplate? lastTemplate;

  /// Convites enviados (ou a enviar) por todos os admins nas últimas 24 h.
  final int sentToday;
  final int dailyLimit;

  bool get overDailyLimit => sentToday >= dailyLimit;

  factory AdminInviteEmailInfo.fromJson(Map<String, dynamic> json) =>
      AdminInviteEmailInfo(
        optedOut: json['opted_out'] == true,
        optedOutAt: _date(json['opted_out_at']),
        sentCount: _int(json['sent_count']),
        lastSentAt: _date(json['last_sent_at']),
        lastTemplate: AdminInviteTemplate.fromDb(
          json['last_template'] as String?,
        ),
        sentToday: _int(json['sent_today']),
        dailyLimit: _int(json['daily_limit']),
      );
}

/// Uma linha do histórico (`admin_list_invites`).
class AdminInviteRow {
  const AdminInviteRow({
    required this.id,
    required this.template,
    required this.recipientName,
    required this.recipientEmail,
    required this.subject,
    required this.status,
    this.error,
    this.createdAt,
    this.sentAt,
    this.optedOutAt,
    this.adminEmail,
    this.totalCount = 0,
  });

  final String id;
  final AdminInviteTemplate? template;
  final String recipientName;
  final String recipientEmail;
  final String subject;
  final AdminInviteStatus status;
  final String? error;
  final DateTime? createdAt;
  final DateTime? sentAt;

  /// Quando este email pediu para não receber (`null` = não pediu).
  final DateTime? optedOutAt;
  final String? adminEmail;
  final int totalCount;

  bool get optedOut => optedOutAt != null;

  factory AdminInviteRow.fromJson(Map<String, dynamic> json) => AdminInviteRow(
    id: json['id'] as String,
    template: AdminInviteTemplate.fromDb(json['template'] as String?),
    recipientName: (json['recipient_name'] as String?) ?? '',
    recipientEmail: (json['recipient_email'] as String?) ?? '',
    subject: (json['subject'] as String?) ?? '',
    status: AdminInviteStatus.fromDb(json['status'] as String?),
    error: json['error'] as String?,
    createdAt: _date(json['created_at']),
    sentAt: _date(json['sent_at']),
    optedOutAt: _date(json['opted_out_at']),
    adminEmail: json['admin_email'] as String?,
    totalCount: _int(json['total_count']),
  );
}

/// Recusa ou falha do envio, com a mensagem já escrita para o admin.
class AdminInviteException implements Exception {
  const AdminInviteException(this.message);

  final String message;

  @override
  String toString() => message;
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

int _int(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v) ?? 0,
  _ => 0,
};
