import 'package:flutter/material.dart' show IconData, Icons;
import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/theme/app_status_presentation.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/widgets/status_timeline.dart';
import '../../jobs/data/cancel_reasons.dart';

/// Como acabou uma proposta que nunca chegou a trabalho. Mesma leitura do
/// cartão de "Os meus trabalhos" (`worker_jobs_screen.dart`): a BD põe
/// `rejected` tanto quando o cliente escolhe outra como quando o pedido
/// expira ou é cancelado (0069, 0070), por isso é o estado do pedido que
/// diz o que aconteceu.
enum WorkerProposalOutcome {
  /// O cliente escolheu a proposta de outro jardineiro.
  chosenOther,

  /// O pedido fechou sem nenhuma proposta aceite (data passou ou 14 dias).
  expired,

  /// O cliente cancelou o pedido antes de escolher.
  cancelled,

  /// O jardineiro retirou a proposta (`superseded`).
  withdrawn,
}

/// `null` enquanto a proposta ainda está viva (pendente num pedido aberto)
/// ou foi aceite: esses estados têm ecrã próprio.
WorkerProposalOutcome? workerProposalOutcome({
  required ProposalStatus proposalStatus,
  required JobStatus jobStatus,
  String? cancelReason,
}) {
  switch (proposalStatus) {
    case ProposalStatus.accepted:
      return null;
    case ProposalStatus.superseded:
      return WorkerProposalOutcome.withdrawn;
    case ProposalStatus.pending:
    case ProposalStatus.rejected:
      if (jobStatus == JobStatus.noResponse ||
          (jobStatus == JobStatus.cancelled &&
              cancelReason == CancelReason.expired)) {
        return WorkerProposalOutcome.expired;
      }
      if (jobStatus == JobStatus.cancelled) {
        return WorkerProposalOutcome.cancelled;
      }
      // Pendente num pedido ainda aberto: não acabou.
      if (proposalStatus == ProposalStatus.pending) return null;
      return WorkerProposalOutcome.chosenOther;
  }
}

/// Badge da AppBar. Os tons seguem o cartão da lista (design A2): cinzento,
/// porque o trabalho nunca foi deste jardineiro. O nó final do timeline usa
/// a mesma cor.
AppStatusPresentation workerProposalOutcomePresentation(
  WorkerProposalOutcome outcome,
) => switch (outcome) {
  WorkerProposalOutcome.chosenOther => ProposalStatus.rejected.presentation,
  WorkerProposalOutcome.expired => const AppStatusPresentation(
    label: 'Expirado',
    color: AppStatusColor.neutral,
  ),
  WorkerProposalOutcome.cancelled => const AppStatusPresentation(
    label: 'Cancelado',
    color: AppStatusColor.neutral,
  ),
  WorkerProposalOutcome.withdrawn => ProposalStatus.superseded.presentation,
};

/// Timeline com dois passos: a proposta enviada e o fim, num nó
/// [StatusTimelineStepState.ended] com o que aconteceu por baixo. Nunca
/// mostra o fluxo do pedido em si (que, escolhido outro, é o trabalho de
/// outra pessoa).
List<StatusTimelineStepData> buildWorkerProposalOutcomeTimeline({
  required WorkerProposalOutcome outcome,
  required DateTime proposalCreatedAt,
  DateTime? endedAt,
  String? cancelReason,
}) {
  final fmt = DateFormat('dd/MM');
  final endedLabel = endedAt == null ? null : fmt.format(endedAt.toLocal());

  final (
    String label,
    AppStatusColor color,
    IconData icon,
    String subtitle,
  ) = switch (outcome) {
    WorkerProposalOutcome.chosenOther => (
      'Outra escolhida',
      AppStatusColor.neutral,
      Icons.close_rounded,
      'O cliente escolheu outra proposta. Não precisas de fazer nada.',
    ),
    WorkerProposalOutcome.expired => (
      'Expirou',
      AppStatusColor.neutral,
      Icons.hourglass_disabled_rounded,
      'O pedido fechou sem nenhuma proposta aceite. Não precisas de '
          'fazer nada.',
    ),
    WorkerProposalOutcome.cancelled => (
      'Cancelado',
      AppStatusColor.neutral,
      Icons.event_busy_rounded,
      [
        'O cliente cancelou o pedido.',
        if (cancelReason != null && cancelReason.isNotEmpty)
          'Motivo: ${CancelReason.label(cancelReason)}.',
        'Não precisas de fazer nada.',
      ].join(' '),
    ),
    WorkerProposalOutcome.withdrawn => (
      'Retirada',
      AppStatusColor.neutral,
      Icons.undo_rounded,
      'Retiraste a tua proposta. O pedido ficou para outros jardineiros.',
    ),
  };

  return [
    StatusTimelineStepData(
      label: 'Proposta enviada',
      statusColor: AppStatusColor.success,
      state: StatusTimelineStepState.completed,
      dateLabel: fmt.format(proposalCreatedAt.toLocal()),
    ),
    StatusTimelineStepData(
      label: label,
      statusColor: color,
      state: StatusTimelineStepState.ended,
      endedIcon: icon,
      // Escolhida outra, o updated_at do pedido mexe com o trabalho do
      // outro jardineiro: sem data, para não enganar.
      dateLabel:
          outcome == WorkerProposalOutcome.expired ||
              outcome == WorkerProposalOutcome.cancelled
          ? endedLabel
          : null,
      subtitle: subtitle,
    ),
  ];
}
