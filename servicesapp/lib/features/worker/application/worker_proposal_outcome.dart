import 'package:flutter/material.dart' show IconData, Icons;
import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/theme/app_status_presentation.dart';
import '../../../core/utils/app_status_presenters.dart';
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
/// porque o trabalho nunca foi deste jardineiro.
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

/// Texto do aviso do topo do corpo (mesmo formato do cancelado/expirado do
/// design A1): título, uma linha de explicação e o ícone.
typedef WorkerProposalOutcomeMessage = ({
  String title,
  String body,
  IconData icon,
});

WorkerProposalOutcomeMessage workerProposalOutcomeMessage({
  required WorkerProposalOutcome outcome,
  DateTime? endedAt,
  String? cancelReason,
}) {
  const nothingToDo = 'Não precisas de fazer nada.';
  return switch (outcome) {
    WorkerProposalOutcome.chosenOther => (
      title: 'O cliente escolheu outra proposta',
      body: nothingToDo,
      icon: Icons.person_off_outlined,
    ),
    WorkerProposalOutcome.expired => (
      title: 'Este pedido expirou',
      body: 'Fechou sem nenhuma proposta aceite. $nothingToDo',
      icon: Icons.hourglass_disabled_rounded,
    ),
    WorkerProposalOutcome.cancelled => (
      title: 'O cliente cancelou o pedido',
      body: [
        if (endedAt != null)
          'Cancelado a ${DateFormat('dd/MM').format(endedAt.toLocal())}.',
        if (cancelReason != null && cancelReason.isNotEmpty)
          'Motivo: ${CancelReason.label(cancelReason)}.',
        nothingToDo,
      ].join(' '),
      icon: Icons.event_busy_outlined,
    ),
    WorkerProposalOutcome.withdrawn => (
      title: 'Retiraste esta proposta',
      body: 'O pedido ficou para outros jardineiros.',
      icon: Icons.undo_rounded,
    ),
  };
}
