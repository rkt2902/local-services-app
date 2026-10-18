import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/help_requests/application/helper_job_state.dart';
import 'package:servicesapp/features/help_requests/data/help_request_model.dart';
import 'package:servicesapp/features/help_requests/presentation/worker_helper_job_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

HelpAcceptanceSummary _acceptance({
  String id = 'a1',
  HelpAcceptanceStatus status = HelpAcceptanceStatus.accepted,
  String jobStatus = 'confirmed',
  String jobId = 'j1',
  String helpRequestId = 'h1',
  double agreedRate = 0,
  double? paymentPerHelper,
  DateTime? createdAt,
}) =>
    HelpAcceptanceSummary(
      id: id,
      helpRequestId: helpRequestId,
      status: status,
      agreedRate: agreedRate,
      broughtEquipment: false,
      createdAt: createdAt ?? DateTime(2026, 10, 1),
      serviceTypeName: 'Poda',
      principalName: 'Rui',
      jobStatus: jobStatus,
      jobId: jobId,
      principalWorkerId: 'p1',
      paymentPerHelper: paymentPerHelper,
    );

void main() {
  group('helperJobStage', () {
    test('pendente enquanto o pedido existe', () {
      expect(helperJobStage(HelpAcceptanceStatus.pending, 'confirmed'),
          HelperJobStage.pending);
      expect(helperJobStage(HelpAcceptanceStatus.pending, 'cancelled'),
          HelperJobStage.closed);
    });

    test('aceite segue o estado do trabalho', () {
      expect(helperJobStage(HelpAcceptanceStatus.accepted, 'confirmed'),
          HelperJobStage.accepted);
      expect(helperJobStage(HelpAcceptanceStatus.accepted, 'awaiting_confirmation'),
          HelperJobStage.workDone);
      expect(helperJobStage(HelpAcceptanceStatus.accepted, 'completed'),
          HelperJobStage.completed);
      expect(helperJobStage(HelpAcceptanceStatus.accepted, 'no_response'),
          HelperJobStage.closed);
    });

    test('recusada ou desistida fica fechada', () {
      expect(helperJobStage(HelpAcceptanceStatus.rejected, 'confirmed'),
          HelperJobStage.closed);
      expect(helperJobStage(HelpAcceptanceStatus.cancelled, 'completed'),
          HelperJobStage.closed);
    });
  });

  test('helperClosedLabel distingue cancelamento, expiração e recusa', () {
    expect(helperClosedLabel(HelpAcceptanceStatus.accepted, 'cancelled'),
        'Trabalho cancelado');
    expect(helperClosedLabel(HelpAcceptanceStatus.pending, 'no_response'),
        'Pedido expirado');
    expect(helperClosedLabel(HelpAcceptanceStatus.rejected, 'confirmed'),
        'Não selecionado');
    expect(helperClosedLabel(HelpAcceptanceStatus.cancelled, 'confirmed'),
        'Já não estás na equipa');
  });

  group('helperJobActions', () {
    test('pendente: só retirar candidatura, sem contacto', () {
      final a = helperJobActions(_acceptance(status: HelpAcceptanceStatus.pending));
      expect(a.canWithdrawApplication, isTrue);
      expect(a.canGiveUp, isFalse);
      expect(a.canRatePrincipal, isFalse);
      expect(a.showsContact, isFalse);
    });

    test('aceite e confirmado: desistir e contacto', () {
      final a = helperJobActions(_acceptance());
      expect(a.canWithdrawApplication, isFalse);
      expect(a.canGiveUp, isTrue);
      expect(a.showsContact, isTrue);
    });

    test('trabalho feito: contacto, sem desistir', () {
      final a = helperJobActions(_acceptance(jobStatus: 'awaiting_confirmation'));
      expect(a.canGiveUp, isFalse);
      expect(a.showsContact, isTrue);
      expect(a.canRatePrincipal, isFalse);
    });

    test('concluído: avaliar o responsável', () {
      final a = helperJobActions(_acceptance(jobStatus: 'completed'));
      expect(a.canRatePrincipal, isTrue);
      expect(a.canGiveUp, isFalse);
    });

    test('cancelado: nada', () {
      final a = helperJobActions(_acceptance(jobStatus: 'cancelled'));
      expect(a.canGiveUp || a.showsContact || a.canRatePrincipal, isFalse);
    });
  });

  group('findHelperAcceptanceFor', () {
    final old = _acceptance(
      id: 'old',
      status: HelpAcceptanceStatus.rejected,
      createdAt: DateTime(2026, 9, 1),
    );
    final accepted = _acceptance(id: 'acc', createdAt: DateTime(2026, 9, 2));
    final other = _acceptance(id: 'other', jobId: 'j2', helpRequestId: 'h2');

    test('pelo id do pedido, preferindo a aceite', () {
      expect(findHelperAcceptanceFor([old, accepted, other], 'j1')?.id, 'acc');
    });

    test('pelo id do pedido de ajuda', () {
      expect(findHelperAcceptanceFor([old, other], 'h2')?.id, 'other');
    });

    test('sem correspondência devolve null', () {
      expect(findHelperAcceptanceFor([old, other], 'x'), isNull);
    });
  });

  test('helpActionErrorMessage: BD sem a função dá mensagem calma', () {
    final missing = PostgrestException(message: 'not found', code: 'PGRST202');
    expect(helpActionErrorMessage(missing), contains('ainda não está disponível'));
    final other = PostgrestException(message: 'boom', code: 'P0001');
    expect(helpActionErrorMessage(other), isNot(contains('ainda não está disponível')));
  });

  group('helperRateLabel', () {
    test('aceite mostra o valor acordado com vírgula', () {
      expect(helperRateLabel(_acceptance(agreedRate: 12.5)), '12,50 €/h acordado');
    });

    test('pendente mostra a sugestão do pedido de ajuda', () {
      expect(
        helperRateLabel(_acceptance(
          status: HelpAcceptanceStatus.pending,
          paymentPerHelper: 9,
        )),
        'Sugestão: 9,00 €/h',
      );
    });

    test('sem valor fica a combinar', () {
      expect(
        helperRateLabel(_acceptance(status: HelpAcceptanceStatus.pending)),
        'Valor a combinar',
      );
    });
  });

  test('fromJson lê payment_per_helper e aceita a BD antiga sem ele', () {
    final base = {
      'id': 'a1',
      'help_request_id': 'h1',
      'status': 'pending',
      'agreed_rate': 0,
      'brought_equipment': false,
      'created_at': '2026-10-01T10:00:00Z',
    };
    expect(HelpAcceptanceSummary.fromJson(base).paymentPerHelper, isNull);
    expect(
      HelpAcceptanceSummary.fromJson({...base, 'payment_per_helper': 11.5})
          .paymentPerHelper,
      11.5,
    );
  });

  test('timeline do ajudante: passo atual e fecho', () {
    final steps = helperTimelineSteps(
      _acceptance(jobStatus: 'awaiting_confirmation'),
      HelperJobStage.workDone,
    );
    expect(steps.map((s) => s.label),
        ['Candidatura', 'Aceite', 'Trabalho feito', 'Concluído']);
    expect(steps[2].subtitle, isNotNull);

    final closed = helperTimelineSteps(
      _acceptance(status: HelpAcceptanceStatus.rejected),
      HelperJobStage.closed,
    );
    expect(closed.last.label, 'Não selecionado');
  });
}
