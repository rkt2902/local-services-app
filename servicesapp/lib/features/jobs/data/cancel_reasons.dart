abstract class CancelReason {
  static const personalIssue = 'personal_issue';
  static const scheduleConflict = 'schedule_conflict';
  static const noLongerNeeded = 'no_longer_needed'; // client only
  static const other = 'other';

  /// Posto pelo cron (migration 0046): trabalho confirmado que passou 3
  /// dias da data sem ser marcado como concluído. Nunca escolhido na UI.
  static const expired = 'expired';

  /// Posto pelo painel de suporte (migration 0079, `admin_cancel_job`).
  /// `cancelled_by` fica vazio. Nunca escolhido na UI da app.
  static const support = 'support';

  static String label(String code) {
    switch (code) {
      case personalIssue:
        return 'Imprevisto pessoal';
      case scheduleConflict:
        return 'Conflito de horário';
      case noLongerNeeded:
        return 'Já não preciso do serviço';
      case other:
        return 'Outra razão';
      case expired:
        return 'Expirou sem ser concluído';
      case support:
        return 'Cancelado pelo suporte';
      default:
        return code;
    }
  }
}
