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
List<StatusTimelineStepData> buildJobTimeline(JobRequest job) {
  final dateFmt = DateFormat('dd/MM');
  final steps = <StatusTimelineStepData>[];

  steps.add(StatusTimelineStepData(
    label: 'Pedido criado',
    statusColor: AppStatusColor.success,
    state: StatusTimelineStepState.completed,
    dateLabel: dateFmt.format(job.createdAt),
  ));

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
      String? proposalNote;
      bool noteIsWarning = false;
      if (job.rescheduleStatus == RescheduleStatus.accepted) {
        proposalNote = 'Data remarcada';
      } else if (job.rescheduleStatus == RescheduleStatus.pending) {
        proposalNote = 'Remarcação pendente';
        noteIsWarning = true;
      }
      steps.add(StatusTimelineStepData(
        label: 'Proposta aceite',
        statusColor: AppStatusColor.success,
        state: StatusTimelineStepState.completed,
        dateLabel:
            job.confirmedDate != null ? dateFmt.format(job.confirmedDate!) : null,
        note: proposalNote,
        noteIsWarning: noteIsWarning,
      ));

      final markedDone = job.status == JobStatus.awaitingConfirmation ||
          job.status == JobStatus.completed;
      steps.add(StatusTimelineStepData(
        // Curto de propósito e distinto de "Concluído" (passo seguinte) —
        // este nó é "o worker diz que terminou", não "o cliente confirmou".
        label: 'Trabalho feito',
        statusColor:
            markedDone ? AppStatusColor.success : AppStatusColor.neutral,
        state: markedDone
            ? StatusTimelineStepState.completed
            : StatusTimelineStepState.future,
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
