
import '../../../core/constants/enums.dart';
import '../../../core/utils/error_utils.dart';
import '../../worker/application/worker_job_rules.dart';
import '../data/help_request_model.dart';

/// Em que ponto está uma candidatura de ajudante, vista pelo próprio
/// ajudante no ecrã `/worker/help/:acceptanceId`.
enum HelperJobStage {
  /// Candidatura enviada, à espera da decisão do responsável.
  pending,

  /// Aceite na equipa, trabalho confirmado e por fazer.
  accepted,

  /// O responsável marcou o trabalho como feito; falta o cliente confirmar.
  workDone,

  /// Trabalho concluído.
  completed,

  /// Já não vai acontecer para este ajudante: não selecionado, desistiu,
  /// foi retirado da equipa, pedido cancelado ou expirado.
  closed,
}

HelperJobStage helperJobStage(HelpAcceptanceStatus status, String jobStatus) {
  final jobDead = jobStatus == JobStatus.cancelled.value ||
      jobStatus == JobStatus.noResponse.value;
  switch (status) {
    case HelpAcceptanceStatus.pending:
      return jobDead ? HelperJobStage.closed : HelperJobStage.pending;
    case HelpAcceptanceStatus.rejected:
    case HelpAcceptanceStatus.cancelled:
      return HelperJobStage.closed;
    case HelpAcceptanceStatus.accepted:
      if (jobDead) return HelperJobStage.closed;
      if (jobStatus == JobStatus.awaitingConfirmation.value) {
        return HelperJobStage.workDone;
      }
      if (jobStatus == JobStatus.completed.value) {
        return HelperJobStage.completed;
      }
      return HelperJobStage.accepted;
  }
}

/// Etiqueta curta do estado final de uma candidatura fechada.
String helperClosedLabel(HelpAcceptanceStatus status, String jobStatus) {
  final override = helperHistoryLabel(status, jobStatus);
  if (override != null) return override;
  return switch (status) {
    HelpAcceptanceStatus.rejected => 'Não selecionado',
    HelpAcceptanceStatus.cancelled => 'Já não estás na equipa',
    _ => 'Terminado',
  };
}

/// Ações e dados que o ecrã do ajudante pode mostrar em cada estado.
class HelperJobActions {
  const HelperJobActions({
    required this.canWithdrawApplication,
    required this.canGiveUp,
    this.giveUpClosedByJobDay = false,
    required this.canRatePrincipal,
    required this.showsContact,
  });

  /// "Retirar candidatura": só enquanto está pendente.
  final bool canWithdrawApplication;

  /// "Desistir": aceite e com o trabalho ainda confirmado, até à véspera
  /// ([helperCanWithdraw]).
  final bool canGiveUp;

  /// Aceite mas já é o dia do trabalho: em vez de "Desistir", o aviso
  /// [helperGiveUpClosedMessage].
  final bool giveUpClosedByJobDay;

  /// "Avaliar o responsável": trabalho concluído.
  final bool canRatePrincipal;

  /// Morada exata, mapa e WhatsApp do responsável: só depois de aceite e
  /// enquanto o trabalho existir.
  final bool showsContact;
}

HelperJobActions helperJobActions(HelpAcceptanceSummary acceptance) {
  final stage = helperJobStage(acceptance.status, acceptance.jobStatus);
  return HelperJobActions(
    canWithdrawApplication: stage == HelperJobStage.pending,
    canGiveUp: stage == HelperJobStage.accepted &&
        helperCanWithdraw(
          acceptance.jobStatus,
          confirmedDate: acceptance.confirmedDate,
        ),
    giveUpClosedByJobDay: stage == HelperJobStage.accepted &&
        helperGiveUpClosedByJobDay(
          acceptance.jobStatus,
          confirmedDate: acceptance.confirmedDate,
        ),
    canRatePrincipal:
        stage == HelperJobStage.completed && acceptance.jobId.isNotEmpty,
    showsContact: stage == HelperJobStage.accepted ||
        stage == HelperJobStage.workDone ||
        stage == HelperJobStage.completed,
  );
}

/// Candidatura que corresponde a uma notificação: `relatedId` pode ser o
/// id do pedido (`job_id`) ou do pedido de ajuda. Prefere a candidatura
/// aceite, depois a mais recente. `null` quando nenhuma corresponde.
HelpAcceptanceSummary? findHelperAcceptanceFor(
  List<HelpAcceptanceSummary> acceptances,
  String relatedId,
) {
  final matches = acceptances
      .where((a) => a.jobId == relatedId || a.helpRequestId == relatedId)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  if (matches.isEmpty) return null;
  return matches
          .where((a) => a.status == HelpAcceptanceStatus.accepted)
          .firstOrNull ??
      matches.first;
}

/// Mensagem de erro das ações de equipa e de candidatura. Com a BD ainda
/// sem a função (PostgREST `PGRST202`), uma mensagem calma em vez de um
/// erro genérico.
String helpActionErrorMessage(Object error) {
  // As RPCs da 0049 recusam com mensagens já em português (P0001).
  return rpcErrorMessage(
    error,
    unavailableMessage:
        'Esta opção ainda não está disponível. Tenta novamente mais tarde.',
  );
}
