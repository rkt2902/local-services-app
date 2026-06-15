abstract class CancelReason {
  static const personalIssue = 'personal_issue';
  static const scheduleConflict = 'schedule_conflict';
  static const noLongerNeeded = 'no_longer_needed'; // client only
  static const other = 'other';

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
      default:
        return code;
    }
  }
}
