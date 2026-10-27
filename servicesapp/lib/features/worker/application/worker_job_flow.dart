import '../../../core/constants/enums.dart';
import '../../../core/models/job_flow_stage.dart';

/// Fase do stepper (design A12) para o jardineiro responsável. `null` nos
/// estados em que o fluxo acabou sem trabalho (proposta recusada ou
/// retirada, pedido cancelado ou expirado): aí fica o timeline, que diz o
/// que aconteceu.
///
/// [teamPending]: há um pedido de ajudantes por aprovar ou vagas por
/// preencher. Vem do resumo da equipa, nunca da data.
JobFlowStage? workerJobFlowStage({
  required ProposalStatus proposalStatus,
  required JobStatus jobStatus,
  required DateTime? startedAt,
  required bool teamPending,
}) {
  switch (proposalStatus) {
    case ProposalStatus.pending:
      return jobStatus == JobStatus.open ? JobFlowStage.proposal : null;
    case ProposalStatus.rejected:
    case ProposalStatus.superseded:
      return null;
    case ProposalStatus.accepted:
      switch (jobStatus) {
        case JobStatus.confirmed:
          if (startedAt != null || !teamPending) return JobFlowStage.onTheDay;
          return JobFlowStage.team;
        case JobStatus.awaitingConfirmation:
        case JobStatus.completed:
          return JobFlowStage.completed;
        case JobStatus.open:
        case JobStatus.noResponse:
        case JobStatus.cancelled:
          return null;
      }
  }
}
