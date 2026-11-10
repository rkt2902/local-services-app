import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';
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

  group('workerProposalOutcomeMessage', () {
    test('outra escolhida não fala de "Sem resposta"', () {
      final m = workerProposalOutcomeMessage(
        outcome: WorkerProposalOutcome.chosenOther,
      );
      expect(m.title, 'O cliente escolheu outra proposta');
      expect(m.body, 'Não precisas de fazer nada.');
    });

    test('cancelado mostra a data e o motivo', () {
      final m = workerProposalOutcomeMessage(
        outcome: WorkerProposalOutcome.cancelled,
        endedAt: DateTime(2026, 10, 27, 12),
        cancelReason: 'no_longer_needed',
      );
      expect(m.body, contains('Cancelado a 27/10.'));
      expect(m.body, contains('Motivo:'));
    });

    test('badges a cinzento, como na lista', () {
      for (final o in WorkerProposalOutcome.values) {
        expect(
          workerProposalOutcomePresentation(o).color,
          AppStatusColor.neutral,
        );
      }
      expect(
        workerProposalOutcomePresentation(
          WorkerProposalOutcome.withdrawn,
        ).label,
        'Retirada',
      );
    });
  });
}
