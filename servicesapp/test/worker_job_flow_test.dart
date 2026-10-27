import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/models/job_flow_stage.dart';
import 'package:servicesapp/features/help_requests/application/helper_job_state.dart';
import 'package:servicesapp/features/worker/application/worker_job_flow.dart';

void main() {
  JobFlowStage? stage(
    ProposalStatus p,
    JobStatus j, {
    DateTime? startedAt,
    bool teamPending = false,
  }) => workerJobFlowStage(
    proposalStatus: p,
    jobStatus: j,
    startedAt: startedAt,
    teamPending: teamPending,
  );

  test('proposta enviada: Proposta', () {
    expect(
      stage(ProposalStatus.pending, JobStatus.open),
      JobFlowStage.proposal,
    );
  });

  test('aceite com equipa por fechar: Equipa; sem ajudantes: No dia', () {
    expect(
      stage(ProposalStatus.accepted, JobStatus.confirmed, teamPending: true),
      JobFlowStage.team,
    );
    expect(
      stage(ProposalStatus.accepted, JobStatus.confirmed),
      JobFlowStage.onTheDay,
    );
  });

  test('iniciado é No dia mesmo com vagas por preencher', () {
    expect(
      stage(
        ProposalStatus.accepted,
        JobStatus.confirmed,
        startedAt: DateTime(2026, 10, 31, 8),
        teamPending: true,
      ),
      JobFlowStage.onTheDay,
    );
  });

  test('dado como feito: Feito', () {
    expect(
      stage(ProposalStatus.accepted, JobStatus.awaitingConfirmation),
      JobFlowStage.completed,
    );
  });

  test('recusada, retirada ou cancelado: sem stepper', () {
    expect(stage(ProposalStatus.rejected, JobStatus.confirmed), isNull);
    expect(stage(ProposalStatus.superseded, JobStatus.open), isNull);
    expect(stage(ProposalStatus.accepted, JobStatus.cancelled), isNull);
  });

  test(
    'ajudante: candidatura em Equipa, aceite No dia, fechada sem stepper',
    () {
      expect(helperJobFlowStage(HelperJobStage.pending), JobFlowStage.team);
      expect(
        helperJobFlowStage(HelperJobStage.accepted),
        JobFlowStage.onTheDay,
      );
      expect(
        helperJobFlowStage(HelperJobStage.workDone),
        JobFlowStage.completed,
      );
      expect(helperJobFlowStage(HelperJobStage.closed), isNull);
    },
  );
}
