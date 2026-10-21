import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/jobs/application/client_proposal_labels.dart';
import 'package:servicesapp/features/jobs/presentation/widgets/client_proposals_view.dart';
import 'package:servicesapp/features/proposals/data/proposal_model.dart';

JobProposal _p(
  String id, {
  double rate = 12,
  double? min = 2,
  double? max = 4,
  int people = 1,
  bool equipment = false,
  DateTime? date,
  String? time,
}) =>
    JobProposal(
      id: id,
      jobId: 'j1',
      workerId: 'w$id',
      hourlyRate: rate,
      estimatedHoursMin: min,
      estimatedHoursMax: max,
      peopleNeeded: people,
      status: ProposalStatus.pending,
      scheduledDate: date,
      scheduledTime: time,
      helpersEquipmentRequired: equipment,
      createdAt: DateTime(2026, 10, 18),
    );

ClientProposalCardViewData _card(String name, {bool recommended = false}) =>
    ClientProposalCardViewData(
      proposalId: 'p-$name',
      workerId: 'w-$name',
      workerName: name,
      ratingLabel: recommended ? '4,9 · 38 avaliações' : null,
      priceLabel: '24 a 48 €',
      priceDetailLabel: '2 a 4h · 12,00 €/h',
      scheduleLabel: 'Qui, 22/10 · 9:00',
      teamLabel: recommended ? 'Equipa de 2' : null,
      recommended: recommended,
      confirmation: const ClientProposalConfirmationViewData(
        summaryMetaLabel: 'Qui, 22/10 · 9:00 · 2 a 4h',
        infoLines: [
          ClientProposalInfoLine(
            icon: Icons.event_repeat_outlined,
            label: 'Podes remarcar ou cancelar até à véspera do trabalho.',
          ),
        ],
        confirmActionLabel: 'Aceitar proposta · 24 a 48 €',
      ),
    );

Widget _screen(
  AsyncValue<ClientProposalsViewData> data, {
  Future<ClientProposalAcceptResult> Function(String)? onAccept,
  ValueChanged<ClientProposalCardViewData>? onAccepted,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ClientProposalsView(
        dataAsync: data,
        onBack: () {},
        onRetry: () {},
        onOpenWorkerProfile: (_) {},
        onAcceptProposal: onAccept ??
            (_) async => const ClientProposalAcceptResult.accepted(),
        onProposalAccepted: onAccepted ?? (_) {},
      ),
    ),
  );
}

AsyncValue<ClientProposalsViewData> _loaded(
        List<ClientProposalCardViewData> cards) =>
    AsyncData(ClientProposalsViewData(
      headerSubtitle: 'Corte de relva · ${cards.length} propostas',
      orderingLabel:
          'Ordenadas por preço estimado, da mais barata para a mais cara.',
      proposals: cards,
    ));

void main() {
  group('textos dos cartões (design A3)', () {
    test('valor total, horas e preço por hora', () {
      expect(proposalPriceLabel(_p('1')), '24 a 48 €');
      expect(proposalPriceDetailLabel(_p('1')), '2 a 4h · 12,00 €/h');
      expect(proposalPriceLabel(_p('1', min: 1.5, max: null)), '18 €');
      expect(proposalHoursLabel(_p('1', min: 1.5, max: 3)), '1,5 a 3h');
      expect(proposalPriceLabel(_p('1', min: null, max: null)), '12,00 €/h');
      expect(proposalPriceDetailLabel(_p('1', min: null, max: null)), '');
    });

    test('equipa conta no total estimado', () {
      // 12 €/h + ajudante sem equipamento a 75% = 21 €/h.
      expect(proposalPriceLabel(_p('1', people: 2)), '42 a 84 €');
      expect(proposalTeamLabel(_p('1', people: 2)), 'Equipa de 2');
      expect(proposalTeamLabel(_p('1')), isNull);
    });

    test('ordem por total estimado, sem horas no fim', () {
      final list = [
        _p('a', rate: 10, min: null, max: null),
        _p('b', rate: 20, min: 4, max: 6), // 80
        _p('c', rate: 15, min: 2, max: null), // 30
        _p('d', rate: 10, min: 2, people: 3), // 50
      ]..sort(compareProposalsByEstimate);
      expect(list.map((p) => p.id), ['c', 'd', 'b', 'a']);
    });

    test('data, avaliações e recomendada', () {
      final now = DateTime(2026, 10, 19);
      expect(
        proposalScheduleLabel(
          _p('1', date: DateTime(2026, 10, 22), time: '09:00:00'),
          now: now,
        ),
        'Qui, 22/10 · 9:00',
      );
      expect(
          proposalScheduleLabel(_p('1')), 'Data a combinar com o jardineiro');
      expect(proposalRatingLabel((avgRating: 4.9, ratingCount: 38)),
          '4,9 · 38 avaliações');
      expect(proposalRatingLabel((avgRating: 0, ratingCount: 0)), isNull);

      final sorted = [_p('1'), _p('2'), _p('3')];
      final summaries = {
        'w1': (avgRating: 5.0, ratingCount: 2),
        'w2': (avgRating: 4.7, ratingCount: 12),
        'w3': (avgRating: 4.9, ratingCount: 38),
      };
      expect(recommendedProposalId(sorted, (id) => summaries[id]), '3');
      expect(proposalsHeaderSubtitle('Corte de relva', 1),
          'Corte de relva · 1 proposta');
    });
  });

  testWidgets('lista com recomendada e estado sem avaliações', (tester) async {
    await tester.pumpWidget(_screen(_loaded([
      _card('Rui Costa', recommended: true),
      _card('João Pires'),
    ])));
    await tester.pumpAndSettle();

    expect(find.text('Corte de relva · 2 propostas'), findsOneWidget);
    expect(find.text('Recomendada'), findsOneWidget);
    expect(find.text('RC'), findsOneWidget);
    expect(find.text('4,9 · 38 avaliações'), findsOneWidget);
    expect(find.text('Ainda sem avaliações'), findsOneWidget);
    expect(find.text('Equipa de 2'), findsOneWidget);
    expect(find.text('Ver perfil e avaliações'), findsNWidgets(2));
  });

  testWidgets('vazio e erro', (tester) async {
    await tester.pumpWidget(_screen(_loaded(const [])));
    await tester.pumpAndSettle();
    expect(find.text('Ainda sem propostas'), findsOneWidget);

    await tester
        .pumpWidget(_screen(AsyncError(Exception('x'), StackTrace.empty)));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar as propostas'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });

  testWidgets('aceitar: só avança depois de o servidor confirmar',
      (tester) async {
    ClientProposalCardViewData? accepted;
    await tester.pumpWidget(_screen(
      _loaded([_card('Rui Costa', recommended: true)]),
      onAccepted: (p) => accepted = p,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Escolher'));
    await tester.pumpAndSettle();
    expect(find.text('Aceitar esta proposta?'), findsOneWidget);
    expect(find.text('Podes remarcar ou cancelar até à véspera do trabalho.'),
        findsOneWidget);

    await tester.tap(find.text('Aceitar proposta · 24 a 48 €'));
    await tester.pumpAndSettle();
    expect(find.text('Aceitar esta proposta?'), findsNothing);
    expect(accepted?.workerName, 'Rui Costa');
  });

  testWidgets('proposta indisponível fica na folha e volta à lista',
      (tester) async {
    var accepted = false;
    await tester.pumpWidget(_screen(
      _loaded([_card('Ana Lopes')]),
      onAccept: (_) async => const ClientProposalAcceptResult.unavailable(),
      onAccepted: (_) => accepted = true,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Escolher'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceitar proposta · 24 a 48 €'));
    await tester.pumpAndSettle();

    expect(find.text('Esta proposta já não está disponível'), findsOneWidget);
    await tester.tap(find.text('Ver propostas'));
    await tester.pumpAndSettle();
    expect(find.text('Esta proposta já não está disponível'), findsNothing);
    expect(accepted, isFalse);
  });

  testWidgets('erro ao aceitar mostra a mensagem dentro da folha',
      (tester) async {
    await tester.pumpWidget(_screen(
      _loaded([_card('Ana Lopes')]),
      onAccept: (_) async =>
          const ClientProposalAcceptResult.failed('Sem ligação.'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Escolher'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceitar proposta · 24 a 48 €'));
    await tester.pumpAndSettle();

    expect(find.text('Sem ligação.'), findsOneWidget);
    expect(find.text('Aceitar esta proposta?'), findsOneWidget);
  });
}
