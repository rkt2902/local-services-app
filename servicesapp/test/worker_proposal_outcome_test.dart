import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';
import 'package:servicesapp/core/widgets/status_timeline.dart';
import 'package:servicesapp/features/jobs/data/cancel_reasons.dart';
import 'package:servicesapp/features/worker/application/worker_proposal_outcome.dart';

void main() {
  group('workerProposalOutcome', () {
    WorkerProposalOutcome? outcome(
      ProposalStatus p,
      JobStatus j, {
      String? reason,
    }) => workerProposalOutcome(
      proposalStatus: p,
      jobStatus: j,
      cancelReason: reason,
    );

    test('recusada com o pedido a seguir com outro: outra escolhida', () {
      for (final j in [
        JobStatus.confirmed,
        JobStatus.awaitingConfirmation,
        JobStatus.completed,
        JobStatus.open,
      ]) {
        expect(
          outcome(ProposalStatus.rejected, j),
          WorkerProposalOutcome.chosenOther,
        );
      }
    });

    test('recusada porque o pedido expirou', () {
      expect(
        outcome(ProposalStatus.rejected, JobStatus.noResponse),
        WorkerProposalOutcome.expired,
      );
      expect(
        outcome(
          ProposalStatus.rejected,
          JobStatus.cancelled,
          reason: CancelReason.expired,
        ),
        WorkerProposalOutcome.expired,
      );
    });

    test('recusada porque o cliente cancelou', () {
      expect(
        outcome(ProposalStatus.rejected, JobStatus.cancelled),
        WorkerProposalOutcome.cancelled,
      );
    });

    test('retirada', () {
      expect(
        outcome(ProposalStatus.superseded, JobStatus.open),
        WorkerProposalOutcome.withdrawn,
      );
    });

    test('pendente num pedido aberto ou aceite: sem fim', () {
      expect(outcome(ProposalStatus.pending, JobStatus.open), isNull);
      expect(outcome(ProposalStatus.accepted, JobStatus.cancelled), isNull);
    });

    test('pendente num pedido que fechou conta como fechada', () {
      expect(
        outcome(ProposalStatus.pending, JobStatus.noResponse),
        WorkerProposalOutcome.expired,
      );
    });
  });

  group('buildWorkerProposalOutcomeTimeline', () {
    test('proposta enviada e um nó final sem pulso, com a explicação', () {
      final steps = buildWorkerProposalOutcomeTimeline(
        outcome: WorkerProposalOutcome.chosenOther,
        proposalCreatedAt: DateTime(2026, 10, 26),
        endedAt: DateTime(2026, 10, 28),
      );
      expect(steps, hasLength(2));
      expect(steps.first.label, 'Proposta enviada');
      expect(steps.first.state, StatusTimelineStepState.completed);
      expect(steps.first.dateLabel, '26/10');
      expect(steps.last.label, 'Outra escolhida');
      expect(steps.last.state, StatusTimelineStepState.ended);
      // A data do pedido mexe com o trabalho do outro: não aparece.
      expect(steps.last.dateLabel, isNull);
      expect(steps.last.subtitle, contains('escolheu outra proposta'));
      expect(steps.any((s) => s.label == 'Sem resposta'), isFalse);
    });

    test('cancelado mostra a data e o motivo', () {
      final steps = buildWorkerProposalOutcomeTimeline(
        outcome: WorkerProposalOutcome.cancelled,
        proposalCreatedAt: DateTime(2026, 10, 26),
        endedAt: DateTime(2026, 10, 27),
        cancelReason: 'no_longer_needed',
      );
      expect(steps.last.dateLabel, '27/10');
      expect(steps.last.subtitle, contains('Motivo:'));
    });

    test('badge e nó final têm a mesma cor', () {
      for (final o in WorkerProposalOutcome.values) {
        final steps = buildWorkerProposalOutcomeTimeline(
          outcome: o,
          proposalCreatedAt: DateTime(2026, 10, 26),
        );
        expect(
          steps.last.statusColor,
          workerProposalOutcomePresentation(o).color,
        );
        expect(steps.last.statusColor, AppStatusColor.neutral);
      }
    });
  });
}
