import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/help_requests/data/help_request_model.dart';
import 'package:servicesapp/features/worker/application/worker_job_rules.dart';

HelpRequest _hr(String id, HelpRequestStatus status, {int slots = 2}) =>
    HelpRequest(
      id: id,
      jobId: 'j1',
      proposalId: 'p1',
      slotsNeeded: slots,
      status: status,
      equipmentRequired: false,
      createdPostConfirmation: true,
      createdAt: DateTime(2026, 10, 1),
    );

HelpAcceptance _candidate(String id, HelpAcceptanceStatus status) =>
    HelpAcceptance(
      id: id,
      helpRequestId: 'h1',
      workerId: 'w$id',
      status: status,
      agreedRate: 0,
      broughtEquipment: false,
      createdAt: DateTime(2026, 10, 2),
    );

void main() {
  final today = DateTime(2026, 10, 18, 15, 30);

  group('WorkerJobDayRules.canCancelOrReschedule (cancel_job/propose_reschedule)', () {
    test('sem data combinada não há limite', () {
      expect(
        WorkerJobDayRules.canCancelOrReschedule(confirmedDate: null, today: today),
        isTrue,
      );
    });

    test('amanhã ainda dá, mesmo a menos de 24h', () {
      expect(
        WorkerJobDayRules.canCancelOrReschedule(
          confirmedDate: DateTime(2026, 10, 19),
          today: DateTime(2026, 10, 18, 23, 50),
        ),
        isTrue,
      );
    });

    test('no próprio dia ou depois já não dá', () {
      expect(
        WorkerJobDayRules.canCancelOrReschedule(
            confirmedDate: DateTime(2026, 10, 18), today: today),
        isFalse,
      );
      expect(
        WorkerJobDayRules.canCancelOrReschedule(
            confirmedDate: DateTime(2026, 10, 10), today: today),
        isFalse,
      );
    });
  });

  group('WorkerJobDayRules atraso (auto_expire_jobs, 0046)', () {
    test('só está atrasado depois do dia do trabalho', () {
      expect(
        WorkerJobDayRules.isOverdue(confirmedDate: DateTime(2026, 10, 18), today: today),
        isFalse,
      );
      expect(
        WorkerJobDayRules.isOverdue(confirmedDate: DateTime(2026, 10, 17), today: today),
        isTrue,
      );
      expect(WorkerJobDayRules.isOverdue(confirmedDate: null, today: today), isFalse);
    });

    test('último dia para concluir é a data + 3 dias', () {
      expect(
        WorkerJobDayRules.lastDayToComplete(DateTime(2026, 10, 15)),
        DateTime(2026, 10, 18),
      );
      expect(
        WorkerJobDayRules.overdueMessage(DateTime(2026, 10, 15)),
        'A data já passou. Marca como concluído até 18/10 ou o pedido expira.',
      );
    });
  });

  group('jobUnavailableReason', () {
    test('aberto não tem motivo', () {
      expect(jobUnavailableReason(JobStatus.open), isNull);
    });

    test('outro jardineiro, cancelado, expirado', () {
      expect(jobUnavailableReason(JobStatus.confirmed),
          'Outro jardineiro ficou com este pedido.');
      expect(jobUnavailableReason(JobStatus.cancelled), 'O pedido foi cancelado.');
      expect(jobUnavailableReason(JobStatus.cancelled, cancelReason: 'expired'),
          'O pedido expirou.');
      expect(jobUnavailableReason(JobStatus.noResponse),
          'O pedido expirou sem nenhuma proposta aceite.');
    });
  });

  group('inactiveJobMessage (cartão cancelado ou expirado)', () {
    test('cancelado pelo cliente: data, motivo e "não precisas de fazer nada"', () {
      final m = inactiveJobMessage(
        cancelReason: 'no_longer_needed',
        cancelledByMe: false,
        endedAt: DateTime(2026, 10, 20, 10),
      );
      expect(m.title, 'O cliente cancelou este trabalho');
      expect(m.body,
          'Cancelado a 20/10. Motivo: Já não preciso do serviço. Não precisas de fazer nada.');
      expect(m.expired, isFalse);
    });

    test('cancelado por mim, sem motivo nem data', () {
      final m = inactiveJobMessage(cancelReason: null, cancelledByMe: true);
      expect(m.title, 'Cancelaste este trabalho');
      expect(m.body, isEmpty);
    });

    test('expirado depois da data e sem resposta', () {
      final m = inactiveJobMessage(cancelReason: 'expired', cancelledByMe: false);
      expect(m.title, 'Este trabalho expirou');
      expect(m.expired, isTrue);
      final n = inactiveJobMessage(
          cancelReason: null, cancelledByMe: false, noResponse: true);
      expect(n.title, 'Este pedido expirou');
      expect(n.expired, isTrue);
    });
  });

  group('helpTeamSummary (cartão Equipa)', () {
    test('sem pedido ativo devolve null (mostra "Preciso de ajudantes")', () {
      expect(helpTeamSummary(const [], const {}), isNull);
      expect(
        helpTeamSummary([_hr('h1', HelpRequestStatus.cancelled)], const {}),
        isNull,
      );
    });

    test('pendente de aprovação do cliente', () {
      final s = helpTeamSummary([_hr('h1', HelpRequestStatus.pendingApproval)], const {});
      expect(s?.label, 'À espera de aprovação do cliente');
      expect(s?.awaitingApproval, isTrue);
    });

    test('vagas preenchidas e candidatos por decidir', () {
      final s = helpTeamSummary(
        [_hr('h1', HelpRequestStatus.open)],
        {
          'h1': [
            _candidate('1', HelpAcceptanceStatus.accepted),
            _candidate('2', HelpAcceptanceStatus.pending),
            _candidate('3', HelpAcceptanceStatus.pending),
            _candidate('4', HelpAcceptanceStatus.pending),
            _candidate('5', HelpAcceptanceStatus.rejected),
          ],
        },
      );
      expect(s?.label,
          'Ajudantes: 1 de 2 vagas preenchidas · 3 candidatos por decidir');
      expect(s?.awaitingApproval, isFalse);
      expect(s?.slots, 2);
      expect(s?.filled, 1);
      expect(s?.undecided, 3);
    });

    test('singular e candidatos ainda a carregar', () {
      expect(
        helpTeamSummary([_hr('h1', HelpRequestStatus.filled, slots: 1)], {
          'h1': [_candidate('1', HelpAcceptanceStatus.accepted)],
        })?.label,
        'Ajudantes: 1 de 1 vaga preenchida',
      );
      expect(
        helpTeamSummary([_hr('h1', HelpRequestStatus.open)], {'h1': null})?.label,
        'Ajudantes: 2 vagas',
      );
    });
  });

  group('cartões do ajudante', () {
    test('aceite num trabalho cancelado passa a histórico', () {
      expect(helperCardKind(HelpAcceptanceStatus.accepted, 'cancelled'),
          HelperCardKind.history);
      expect(helperCardKind(HelpAcceptanceStatus.accepted, 'confirmed'),
          HelperCardKind.active);
      expect(helperCardKind(HelpAcceptanceStatus.pending, 'open'),
          HelperCardKind.pending);
      expect(helperCardKind(HelpAcceptanceStatus.rejected, 'confirmed'),
          HelperCardKind.history);
    });

    test('Desistir só até à véspera do trabalho', () {
      final today = DateTime(2026, 10, 21);
      expect(
        helperCanWithdraw('confirmed',
            confirmedDate: DateTime(2026, 10, 22), today: today),
        isTrue,
      );
      expect(
        helperCanWithdraw('confirmed', confirmedDate: today, today: today),
        isFalse,
      );
      expect(
        helperGiveUpClosedByJobDay('confirmed',
            confirmedDate: today, today: today),
        isTrue,
      );
      expect(
        helperGiveUpClosedByJobDay('completed',
            confirmedDate: today, today: today),
        isFalse,
      );
    });

    test('Desistir só com o trabalho confirmado', () {
      expect(helperCanWithdraw('confirmed'), isTrue);
      expect(helperCanWithdraw('awaiting_confirmation'), isFalse);
      expect(helperCanWithdraw('cancelled'), isFalse);
      expect(helperCanWithdraw('completed'), isFalse);
    });

    test('rejeitado por cancelamento diz "Trabalho cancelado"', () {
      expect(helperHistoryLabel(HelpAcceptanceStatus.rejected, 'cancelled'),
          'Trabalho cancelado');
      expect(helperHistoryLabel(HelpAcceptanceStatus.rejected, 'confirmed'), isNull);
      expect(helperHistoryLabel(HelpAcceptanceStatus.cancelled, 'cancelled'), isNull);
    });
  });
}
