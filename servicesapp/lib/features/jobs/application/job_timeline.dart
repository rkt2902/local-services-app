import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/widgets/status_timeline.dart';
import '../data/cancel_reasons.dart';
import '../data/job_model.dart';

List<TimelineStep> buildJobTimeline(JobRequest job) {
  final fmt = DateFormat('dd/MM/yyyy');
  final steps = <TimelineStep>[];

  steps.add(TimelineStep(
    label: 'Pedido criado',
    state: TimelineStepState.done,
    subtitle: fmt.format(job.createdAt),
  ));

  switch (job.status) {
    case JobStatus.open:
      steps.add(const TimelineStep(
        label: 'À espera de proposta',
        state: TimelineStepState.current,
      ));

    case JobStatus.noResponse:
      steps.add(const TimelineStep(
        label: 'Sem resposta em 48h',
        state: TimelineStepState.cancelled,
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
      steps.add(TimelineStep(
        label: 'Proposta aceite',
        state: TimelineStepState.done,
        subtitle:
            job.confirmedDate != null ? fmt.format(job.confirmedDate!) : null,
        note: proposalNote,
        noteIsWarning: noteIsWarning,
      ));

      final markedDone = job.status == JobStatus.awaitingConfirmation ||
          job.status == JobStatus.completed;
      steps.add(TimelineStep(
        label: 'Marcado como concluído',
        state:
            markedDone ? TimelineStepState.done : TimelineStepState.future,
      ));

      steps.add(TimelineStep(
        label: 'Confirmado pelo cliente',
        state: switch (job.status) {
          JobStatus.completed => TimelineStepState.done,
          JobStatus.awaitingConfirmation => TimelineStepState.current,
          _ => TimelineStepState.future,
        },
      ));

    case JobStatus.cancelled:
      if (job.confirmedDate != null) {
        steps.add(TimelineStep(
          label: 'Proposta aceite',
          state: TimelineStepState.done,
          subtitle: fmt.format(job.confirmedDate!),
        ));
      }
      steps.add(TimelineStep(
        label: 'Cancelado',
        state: TimelineStepState.cancelled,
        subtitle: job.cancelReason != null
            ? CancelReason.label(job.cancelReason!)
            : null,
      ));
  }

  return steps;
}
