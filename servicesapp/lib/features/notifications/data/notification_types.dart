abstract class NotificationType {
  static const newJobInRadius = 'new_job_in_radius';
  static const proposalReceived = 'proposal_received';
  static const proposalWithdrawn = 'proposal_withdrawn';
  static const proposalAccepted = 'proposal_accepted';
  static const proposalRejected = 'proposal_rejected';
  static const jobCancelled = 'job_cancelled';
  static const jobReopened = 'job_reopened';
  static const jobMarkedDone = 'job_marked_done';
  static const jobCompleted = 'job_completed';
  static const jobNoResponse = 'job_no_response';

  /// Lembretes do cron `send_job_reminders` (migration 0046): manhã do dia
  /// do trabalho, data passada sem conclusão, conclusão por confirmar.
  static const jobReminder = 'job_reminder';
  static const rescheduleProposed = 'reschedule_proposed';
  static const rescheduleAccepted = 'reschedule_accepted';
  static const rescheduleRejected = 'reschedule_rejected';
  static const helpRequestApproved = 'help_request_approved';
  static const helpAccepted = 'help_accepted';
  static const helpRejected = 'help_rejected';
  static const helpJobCancelled = 'help_job_cancelled';
  static const helpRequestReopened = 'help_request_reopened';
  static const helpWithdrew = 'help_withdrew';

  /// Migration 0048: novo candidato (para o jardineiro responsável, abre a
  /// equipa) e pedido de ajudantes por aprovar (para o cliente).
  static const helpCandidateApplied = 'help_candidate_applied';
  static const helpRequestPendingApproval = 'help_request_pending_approval';

  /// Migration 0049. `relatedId` = id do pedido (`job_requests.id`) em todos.
  ///
  /// [jobUpdated]: o cliente alterou um pedido a que o jardineiro propôs.
  static const jobUpdated = 'job_updated';

  /// Para o ajudante: foi retirado da equipa pelo responsável.
  static const helpRemoved = 'help_removed';

  /// Para o ajudante: o trabalho em que ajuda mudou de data.
  static const helpJobRescheduled = 'help_job_rescheduled';

  /// Para o ajudante: o responsável marcou o trabalho como feito.
  static const helpJobDone = 'help_job_done';

  /// Para o ajudante: o trabalho ficou concluído (pode avaliar).
  static const helpJobCompleted = 'help_job_completed';
}
