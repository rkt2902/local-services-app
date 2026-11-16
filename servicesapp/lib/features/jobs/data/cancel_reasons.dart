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

  /// Pedido aberto fechado porque o suporte suspendeu a conta (0080). Pode
  /// publicar-se de novo depois de a conta voltar a estar ativa.
  static const accountSuspended = 'account_suspended';

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
      case accountSuspended:
        return 'Fechado ao suspender a conta';
      default:
        return code;
    }
  }
}
