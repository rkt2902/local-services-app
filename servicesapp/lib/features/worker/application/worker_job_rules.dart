import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../help_requests/data/help_request_model.dart';
import '../../jobs/data/cancel_reasons.dart';

/// Regras de datas do trabalho confirmado, alinhadas com a BD.
///
/// - `cancel_job` (0043) e `propose_reschedule` (0042) recusam quando
///   `confirmed_date - CURRENT_DATE < 1`: só até ao dia anterior.
/// - `auto_expire_jobs` (0046) expira o trabalho confirmado quando
///   `confirmed_date < today_pt() - 3`: o último dia para marcar como
///   concluído é a data + 3 dias.
/// - `auto_confirm_completed_jobs` (0052) confirma sozinho 48 horas depois
///   de o worker marcar como concluído, sem problema reportado.
/// - `start_job` (0052) só deixa iniciar a partir de 1h antes da hora
///   combinada; sem hora, a partir do dia; sem data, sempre.
abstract final class WorkerJobDayRules {
  /// Dias depois da data combinada em que ainda dá para marcar concluído.
  static const overdueGraceDays = 3;

  /// Horas até o trabalho marcado como concluído ser confirmado sozinho.
  static const autoConfirmHours = 48;

  /// Quanto tempo antes da hora combinada se pode iniciar o trabalho.
  static const startLeadTime = Duration(hours: 1);

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Cancelar e remarcar: só até ao dia anterior ao trabalho. Sem data
  /// combinada (horário flexível) a BD não impõe limite.
  static bool canCancelOrReschedule({
    required DateTime? confirmedDate,
    required DateTime today,
  }) {
    if (confirmedDate == null) return true;
    return _day(confirmedDate).difference(_day(today)).inDays >= 1;
  }

  /// A data combinada já passou e o trabalho continua por concluir.
  static bool isOverdue({
    required DateTime? confirmedDate,
    required DateTime today,
  }) {
    if (confirmedDate == null) return false;
    return _day(confirmedDate).isBefore(_day(today));
  }

  /// Último dia em que o worker ainda pode marcar como concluído antes de o
  /// pedido expirar.
  static DateTime lastDayToComplete(DateTime confirmedDate) =>
      _day(confirmedDate).add(const Duration(days: overdueGraceDays));

  /// Momento a partir do qual "Iniciar trabalho" fica disponível; `null`
  /// quando não há data combinada (sempre disponível). Hora do dispositivo,
  /// que em Portugal coincide com a da BD (Europe/Lisbon).
  static DateTime? startOpensAt({
    required DateTime? confirmedDate,
    required String? confirmedTime,
    required bool confirmedFlexible,
  }) {
    if (confirmedDate == null) return null;
    final day = _day(confirmedDate);
    final time = confirmedTime;
    if (confirmedFlexible || time == null || time.length < 5) return day;
    final parts = time.substring(0, 5).split(':');
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return day;
    return DateTime(day.year, day.month, day.day, hour, minute)
        .subtract(startLeadTime);
  }

  static bool canStart({
    required DateTime? confirmedDate,
    required String? confirmedTime,
    required bool confirmedFlexible,
    required DateTime now,
  }) {
    final opens = startOpensAt(
      confirmedDate: confirmedDate,
      confirmedTime: confirmedTime,
      confirmedFlexible: confirmedFlexible,
    );
    return opens == null || !now.isBefore(opens);
  }

  static String overdueMessage(DateTime confirmedDate) {
    final deadline = DateFormat('dd/MM').format(lastDayToComplete(confirmedDate));
    return 'A data já passou. Marca como concluído até $deadline ou o pedido expira.';
  }

  static const awaitingConfirmationMessage =
      'À espera da confirmação do cliente. Já marcaste este trabalho como '
      'concluído. Se o cliente não responder, fica confirmado '
      'automaticamente $autoConfirmHours horas depois.';
}

/// Porque é que um pedido que o worker abriu já não está disponível para
/// propostas. `null` quando ainda está aberto.
String? jobUnavailableReason(JobStatus status, {String? cancelReason}) {
  switch (status) {
    case JobStatus.open:
      return null;
    case JobStatus.confirmed:
    case JobStatus.awaitingConfirmation:
    case JobStatus.completed:
      return 'Outro jardineiro ficou com este pedido.';
    case JobStatus.cancelled:
      return cancelReason == CancelReason.expired
          ? 'O pedido expirou.'
          : 'O pedido foi cancelado.';
    case JobStatus.noResponse:
      return 'O pedido expirou sem nenhuma proposta aceite.';
  }
}

/// Texto do banner de um trabalho cancelado no ecrã "O meu trabalho".
String cancelledJobBannerMessage({
  required String? cancelReason,
  required bool cancelledByMe,
}) {
  if (cancelReason == CancelReason.expired) {
    return 'Trabalho expirado: passaram ${WorkerJobDayRules.overdueGraceDays} '
        'dias da data sem ser marcado como concluído.';
  }
  final who = cancelledByMe ? 'Cancelaste este trabalho' : 'O cliente cancelou este trabalho';
  if (cancelReason == null || cancelReason.isEmpty) return '$who.';
  return '$who. Motivo: ${CancelReason.label(cancelReason)}.';
}

/// Resumo da equipa de ajudantes de um trabalho, para o cartão "Equipa".
class HelpTeamSummary {
  const HelpTeamSummary({required this.label, required this.awaitingApproval});

  final String label;
  final bool awaitingApproval;
}

/// `null` quando não há nenhum pedido de ajudantes ativo (pendente de
/// aprovação, aberto ou preenchido): aí mostra-se "Preciso de ajudantes".
///
/// [candidatesByHelpRequest]: candidatos por pedido de ajuda; um valor
/// `null` quer dizer "ainda a carregar".
HelpTeamSummary? helpTeamSummary(
  List<HelpRequest> helpRequests,
  Map<String, List<HelpAcceptance>?> candidatesByHelpRequest,
) {
  final active = helpRequests
      .where((hr) => hr.status != HelpRequestStatus.cancelled)
      .toList();
  if (active.isEmpty) return null;

  final approved = active
      .where((hr) => hr.status != HelpRequestStatus.pendingApproval)
      .toList();
  if (approved.isEmpty) {
    return const HelpTeamSummary(
      label: 'À espera de aprovação do cliente',
      awaitingApproval: true,
    );
  }

  var slots = 0;
  var filled = 0;
  var undecided = 0;
  var countsKnown = true;
  for (final hr in approved) {
    slots += hr.slotsNeeded;
    final candidates = candidatesByHelpRequest[hr.id];
    if (candidates == null) {
      countsKnown = false;
      continue;
    }
    filled += candidates
        .where((c) => c.status == HelpAcceptanceStatus.accepted)
        .length;
    undecided += candidates
        .where((c) => c.status == HelpAcceptanceStatus.pending)
        .length;
  }

  final vagas = slots == 1 ? 'vaga' : 'vagas';
  if (!countsKnown) {
    return HelpTeamSummary(label: 'Ajudantes: $slots $vagas', awaitingApproval: false);
  }
  final preenchidas = slots == 1 ? 'preenchida' : 'preenchidas';
  final buffer = StringBuffer('Ajudantes: $filled de $slots $vagas $preenchidas');
  if (undecided > 0) {
    buffer.write(
        ' · $undecided ${undecided == 1 ? 'candidato' : 'candidatos'} por decidir');
  }
  return HelpTeamSummary(label: buffer.toString(), awaitingApproval: false);
}

/// Estado com que um ajudante vê uma candidatura.
enum HelperCardKind { pending, active, history }

/// Uma candidatura aceite num trabalho que já não vai acontecer (cancelado
/// ou expirado) passa a histórico: sem "Desistir" nem WhatsApp.
HelperCardKind helperCardKind(HelpAcceptanceStatus status, String jobStatus) {
  switch (status) {
    case HelpAcceptanceStatus.pending:
      return _jobIsDead(jobStatus) ? HelperCardKind.history : HelperCardKind.pending;
    case HelpAcceptanceStatus.accepted:
      return _jobIsDead(jobStatus) ? HelperCardKind.history : HelperCardKind.active;
    case HelpAcceptanceStatus.rejected:
    case HelpAcceptanceStatus.cancelled:
      return HelperCardKind.history;
  }
}

/// "Desistir" só enquanto o trabalho está confirmado (a RPC
/// `withdraw_help_acceptance` não faz sentido depois disso).
bool helperCanWithdraw(String jobStatus) => jobStatus == JobStatus.confirmed.value;

/// Etiqueta de histórico: as candidaturas rejeitadas em cascata pelo
/// cancelamento do trabalho dizem "Trabalho cancelado", não "Não
/// selecionado". `null` = usar a etiqueta normal do estado.
String? helperHistoryLabel(HelpAcceptanceStatus status, String jobStatus) {
  if (status == HelpAcceptanceStatus.cancelled) return null;
  if (jobStatus == JobStatus.cancelled.value) return 'Trabalho cancelado';
  if (jobStatus == JobStatus.noResponse.value) return 'Pedido expirado';
  return null;
}

bool _jobIsDead(String jobStatus) =>
    jobStatus == JobStatus.cancelled.value ||
    jobStatus == JobStatus.noResponse.value;
