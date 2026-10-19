import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/widgets/status_timeline.dart';
import '../data/cancel_reasons.dart';
import '../data/job_model.dart';

/// Labels dos nós são versões curtas (≤ ~14 caracteres) das de
/// `JobStatusPresentationExtension.presentation()` — essas continuam a
/// servir os badges de estado em toda a app; aqui só o texto do nó muda,
/// nunca `.color`, que continua a vir de `presentation()` (mesma cor em
/// badge e timeline para o mesmo estado).
List<StatusTimelineStepData> buildJobTimeline(JobRequest job, {DateTime? now}) {
  final dateFmt = DateFormat('dd/MM');
  final steps = <StatusTimelineStepData>[];

  // Depois de aceite, o fluxo 3B tem os seus 4 nós e já não mostra a
  // criação do pedido.
  final accepted = job.status == JobStatus.confirmed ||
      job.status == JobStatus.awaitingConfirmation ||
      job.status == JobStatus.completed;
  if (!accepted) {
    steps.add(StatusTimelineStepData(
      label: 'Pedido criado',
      statusColor: AppStatusColor.success,
      state: StatusTimelineStepState.completed,
      dateLabel: dateFmt.format(job.createdAt),
    ));
  }

  switch (job.status) {
    case JobStatus.open:
      final hasProposals = job.proposalCount > 0;
      final current = job.status.presentation(proposalCount: job.proposalCount);
      steps.add(StatusTimelineStepData(
        label: hasProposals ? current.label : 'Sem proposta',
        statusColor: current.color,
        state: StatusTimelineStepState.current,
      ));

    case JobStatus.noResponse:
      final current = job.status.presentation();
      steps.add(StatusTimelineStepData(
        label: current.label,
        statusColor: current.color,
        state: StatusTimelineStepState.current,
      ));

    case JobStatus.confirmed:
    case JobStatus.awaitingConfirmation:
    case JobStatus.completed:
      // Fluxo 3B (design de 2026-10-19): Aceite → Agendado → Em curso →
      // Concluído. "Em curso" é `confirmed` com `startedAt` (migration
      // 0052), sem estado novo na BD.
      final started = job.startedAt != null;
      final markedDone = job.status == JobStatus.awaitingConfirmation ||
          job.status == JobStatus.completed;

      steps.add(const StatusTimelineStepData(
        label: 'Aceite',
        statusColor: AppStatusColor.success,
        state: StatusTimelineStepState.completed,
      ));

      String? scheduleNote;
      bool noteIsWarning = false;
      if (job.rescheduleStatus == RescheduleStatus.accepted) {
        scheduleNote = 'Data remarcada';
      } else if (job.rescheduleStatus == RescheduleStatus.pending) {
        scheduleNote = 'Remarcação pendente';
        noteIsWarning = true;
      }
      final scheduledCurrent = !started && !markedDone;
      steps.add(StatusTimelineStepData(
        label: 'Agendado',
        statusColor: AppStatusColor.success,
        state: scheduledCurrent
            ? StatusTimelineStepState.current
            : StatusTimelineStepState.completed,
        dateLabel:
            job.confirmedDate != null ? dateFmt.format(job.confirmedDate!) : null,
        subtitle: scheduledCurrent
            ? scheduledCountdownLabel(job, now ?? DateTime.now())
            : null,
        note: scheduleNote,
        noteIsWarning: noteIsWarning,
      ));

      final inProgress = started && !markedDone;
      steps.add(StatusTimelineStepData(
        label: 'Em curso',
        statusColor: (inProgress || markedDone)
            ? AppStatusColor.info
            : AppStatusColor.neutral,
        state: inProgress
            ? StatusTimelineStepState.current
            : markedDone
                ? StatusTimelineStepState.completed
                : StatusTimelineStepState.future,
        subtitle: inProgress
            ? 'Iniciado às ${DateFormat('HH:mm').format(job.startedAt!.toLocal())}'
            : null,
      ));

      if (job.status == JobStatus.completed) {
        final current = job.status.presentation();
        steps.add(StatusTimelineStepData(
          label: current.label,
          statusColor: current.color,
          state: StatusTimelineStepState.completed,
        ));
      } else if (job.status == JobStatus.awaitingConfirmation) {
        final current = job.status.presentation();
        steps.add(StatusTimelineStepData(
          label: 'A confirmar',
          statusColor: current.color,
          state: StatusTimelineStepState.current,
          subtitle: 'À espera da confirmação do cliente',
        ));
      } else {
        steps.add(const StatusTimelineStepData(
          label: 'Concluído',
          statusColor: AppStatusColor.neutral,
          state: StatusTimelineStepState.future,
        ));
      }

    case JobStatus.cancelled:
      if (job.confirmedDate != null) {
        steps.add(StatusTimelineStepData(
          label: 'Proposta aceite',
          statusColor: AppStatusColor.success,
          state: StatusTimelineStepState.completed,
          dateLabel: dateFmt.format(job.confirmedDate!),
        ));
      }
      final current = job.status.presentation();
      steps.add(StatusTimelineStepData(
        label: current.label,
        statusColor: current.color,
        state: StatusTimelineStepState.current,
        subtitle: job.cancelReason != null
            ? CancelReason.label(job.cancelReason!)
            : null,
      ));
  }

  return steps;
}

/// "Hoje às 14:00 · daqui a 4h 19min" para o nó "Agendado". Sem data,
/// "Data a combinar"; sem hora, só o dia.
String scheduledCountdownLabel(JobRequest job, DateTime now) {
  final date = job.confirmedDate;
  if (date == null) return 'Data a combinar';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final dayDiff = day.difference(today).inDays;
  final dayLabel = switch (dayDiff) {
    0 => 'Hoje',
    1 => 'Amanhã',
    _ => DateFormat('dd/MM').format(day),
  };
  final time = job.confirmedTime;
  if (job.confirmedFlexible || time == null || time.length < 5) {
    return '$dayLabel · horário flexível';
  }
  final hhmm = time.substring(0, 5);
  final parts = hhmm.split(':');
  final at = DateTime(day.year, day.month, day.day, int.parse(parts[0]),
      int.parse(parts[1]));
  final left = at.difference(now);
  if (left.isNegative || left.inHours >= 24) return '$dayLabel às $hhmm';
  return '$dayLabel às $hhmm · daqui a ${durationLabel(left)}';
}

/// "2h 10min", "45min", "3h".
String durationLabel(Duration d) {
  final minutes = d.inMinutes < 0 ? 0 : d.inMinutes;
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}min';
  if (m == 0) return '${h}h';
  return '${h}h ${m}min';
}
