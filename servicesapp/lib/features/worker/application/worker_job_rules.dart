import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/date_labels.dart';
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

/// "Qui, 23/10 · 9:00" (design A1). Sem data: "Data a combinar"; sem hora
/// fixa: "Qui, 23/10 · horário flexível".
String workerScheduleLabel({
  required DateTime? date,
  required String? time,
  required bool flexible,
  DateTime? now,
}) {
  if (date == null) return 'Data a combinar';
  final day = shortWeekdayDateLabel(date, now: now);
  if (flexible) return '$day · horário flexível';
  final hhmm = _clockLabel(time);
  return hhmm == null ? day : '$day · $hhmm';
}

/// "09:00:00" → "9:00". `null` quando não há hora válida.
String? _clockLabel(String? time) {
  if (time == null || time.length < 5) return null;
  final parts = time.substring(0, 5).split(':');
  final hour = int.tryParse(parts[0]);
  if (hour == null) return null;
  return '$hour:${parts[1]}';
}

/// Texto por baixo de "Iniciar trabalho" (design A1): quando abre, ou o
/// aviso de que o cliente é notificado quando já se pode iniciar.
String startJobHint({
  required bool canStart,
  required DateTime? opensAt,
  required DateTime now,
}) {
  if (canStart || opensAt == null) {
    return 'O cliente recebe um aviso quando começares.';
  }
  final dayOnly = opensAt.hour == 0 && opensAt.minute == 0;
  final sameDay = _isSameDay(opensAt, now);
  final day = sameDay
      ? 'hoje'
      : shortWeekdayDateLabel(opensAt, now: now).toLowerCase();
  if (dayOnly) {
    return sameDay ? 'Disponível a partir de hoje' : 'Disponível a partir de $day';
  }
  return 'Disponível a partir das ${DateFormat('H:mm').format(opensAt)} de $day';
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Cartão de um trabalho que já não vai acontecer, no ecrã "O meu
/// trabalho" (design A1): título, texto e se é o caso "expirou" (ícone de
/// ampulheta a cinzento em vez do calendário a vermelho).
typedef InactiveJobMessage = ({String title, String body, bool expired});

/// [noResponse]: o pedido expirou antes de ser confirmado. [endedAt]: quando
/// o pedido mudou de estado pela última vez (`updated_at`); `null` omite a
/// data.
InactiveJobMessage inactiveJobMessage({
  required String? cancelReason,
  required bool cancelledByMe,
  bool noResponse = false,
  DateTime? endedAt,
}) {
  if (noResponse) {
    return (
      title: 'Este pedido expirou',
      body: 'Não precisas de fazer nada.',
      expired: true,
    );
  }
  if (cancelReason == CancelReason.expired) {
    return (
      title: 'Este trabalho expirou',
      body: 'Passaram ${WorkerJobDayRules.overdueGraceDays} dias da data sem '
          'ser marcado como concluído.',
      expired: true,
    );
  }
  final parts = <String>[
    if (endedAt != null)
      'Cancelado a ${DateFormat('dd/MM').format(endedAt.toLocal())}.',
    if (cancelReason != null && cancelReason.isNotEmpty)
      'Motivo: ${CancelReason.label(cancelReason)}.',
    if (!cancelledByMe) 'Não precisas de fazer nada.',
  ];
  return (
    title: cancelledByMe
        ? 'Cancelaste este trabalho'
        : 'O cliente cancelou este trabalho',
    body: parts.join(' '),
    expired: false,
  );
}

/// Resumo da equipa de ajudantes de um trabalho, para o cartão "Equipa".
class HelpTeamSummary {
  const HelpTeamSummary({
    required this.label,
    required this.awaitingApproval,
    this.slots = 0,
    this.filled,
    this.undecided,
  });

  final String label;
  final bool awaitingApproval;

  /// Vagas aprovadas (soma dos pedidos de ajuda já aprovados).
  final int slots;

  /// Ajudantes aceites e candidatos por decidir; `null` enquanto os
  /// candidatos carregam.
  final int? filled;
  final int? undecided;
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
    return HelpTeamSummary(
      label: 'Ajudantes: $slots $vagas',
      awaitingApproval: false,
      slots: slots,
    );
  }
  final preenchidas = slots == 1 ? 'preenchida' : 'preenchidas';
  final buffer = StringBuffer('Ajudantes: $filled de $slots $vagas $preenchidas');
  if (undecided > 0) {
    buffer.write(
        ' · $undecided ${undecided == 1 ? 'candidato' : 'candidatos'} por decidir');
  }
  return HelpTeamSummary(
    label: buffer.toString(),
    awaitingApproval: false,
    slots: slots,
    filled: filled,
    undecided: undecided,
  );
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

/// "Desistir" só enquanto o trabalho está confirmado e até à véspera: a
/// partir do dia do trabalho `withdraw_help_acceptance` recusa (0055) e só
/// o responsável pode tirar alguém da equipa.
bool helperCanWithdraw(
  String jobStatus, {
  DateTime? confirmedDate,
  DateTime? today,
}) =>
    jobStatus == JobStatus.confirmed.value &&
    WorkerJobDayRules.canCancelOrReschedule(
      confirmedDate: confirmedDate,
      today: today ?? DateTime.now(),
    );

/// Aceite, trabalho por fazer, mas já é o dia: "Desistir" sai e o ecrã
/// explica porquê ([helperGiveUpClosedMessage]).
bool helperGiveUpClosedByJobDay(
  String jobStatus, {
  DateTime? confirmedDate,
  DateTime? today,
}) =>
    jobStatus == JobStatus.confirmed.value &&
    !helperCanWithdraw(jobStatus, confirmedDate: confirmedDate, today: today);

const helperGiveUpClosedMessage =
    'No dia do trabalho já não podes desistir. Se tiveres um imprevisto, '
    'fala com o jardineiro responsável pelo WhatsApp.';

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
