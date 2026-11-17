/// Estado da própria conta (`get_my_account_status`, migration 0080):
/// suspensa pelo suporte e/ou com encerramento marcado. O motivo interno
/// não vem; só a mensagem escrita para a pessoa.
class MyAccountStatus {
  const MyAccountStatus({
    this.suspendedAt,
    this.suspendedMessage,
    this.closingAt,
    this.closingMessage,
  });

  /// Sem suspensão nem encerramento (também o valor quando a base de dados
  /// ainda não tem a 0080).
  static const active = MyAccountStatus();

  final DateTime? suspendedAt;
  final String? suspendedMessage;
  final DateTime? closingAt;
  final String? closingMessage;

  bool get isSuspended => suspendedAt != null;

  factory MyAccountStatus.fromJson(Map<String, dynamic> json) {
    DateTime? date(Object? v) =>
        v is String ? DateTime.tryParse(v)?.toLocal() : null;
    String? text(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    return MyAccountStatus(
      suspendedAt: date(json['suspended_at']),
      suspendedMessage: text(json['suspended_message']),
      closingAt: date(json['closing_at']),
      closingMessage: text(json['closing_message']),
    );
  }
}
