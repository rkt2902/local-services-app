import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/jobs/application/client_proposal_labels.dart';
import 'package:servicesapp/features/jobs/presentation/widgets/client_proposal_detail_view.dart';
import 'package:servicesapp/features/jobs/presentation/widgets/client_proposals_view.dart';
import 'package:servicesapp/features/proposals/data/proposal_model.dart';

JobProposal _p(
  String id, {
  double rate = 12,
  double? min = 2,
  double? max = 4,
  DateTime? date,
  String? time,
  bool expired = false,
  ProposalPricingMode mode = ProposalPricingMode.hourly,
  double? total,
}) =>
    JobProposal(
      id: id,
      jobId: 'j1',
      workerId: 'w$id',
      hourlyRate: rate,
      estimatedHoursMin: min,
      estimatedHoursMax: max,
      peopleNeeded: 1,
      status: ProposalStatus.pending,
      scheduledDate: date,
      scheduledTime: time,
      createdAt: DateTime(2026, 10, 18),
      isExpired: expired,
      pricingMode: mode,
      totalPrice: total,
    );

ClientProposalCardViewData _card(
  String name, {
  bool recommended = false,
  bool fixed = false,
  bool expired = false,
}) =>
    ClientProposalCardViewData(
      proposalId: 'p-$name',
      workerId: 'w-$name',
      workerName: name,
      ratingLabel: recommended ? '4,9 · 38 avaliações' : null,
      priceLabel: fixed ? '450 €' : '25 €/h',
      priceKindLabel: fixed ? 'valor fechado' : 'preço por hora',
      totalLabel: fixed ? '450 €' : 'cerca de 100 a 150 €',
      totalNoteLabel: fixed
          ? 'Fechado. Não muda com as horas.'
          : 'Estimado. Depende das horas feitas.',
      scheduleLabel: 'Qui, 22/10 · 9:00',
      teamLabel: recommended ? 'Leva 1 ajudante' : null,
      recommended: recommended,
      expired: expired,
    );

Widget _list(
  AsyncValue<ClientProposalsViewData> data, {
  ValueChanged<ClientProposalCardViewData>? onOpen,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ClientProposalsView(
        dataAsync: data,
        onBack: () {},
        onRetry: () {},
        onOpenProposal: onOpen ?? (_) {},
      ),
    ),
  );
}

AsyncValue<ClientProposalsViewData> _loaded(
        List<ClientProposalCardViewData> cards) =>
    AsyncData(ClientProposalsViewData(
      headerSubtitle: 'Corte de relva · ${cards.length} propostas',
      proposals: cards,
    ));

const _detail = ClientProposalDetailViewData(
  proposalId: 'p1',
  workerId: 'w1',
  workerName: 'Rui Costa',
  priceTitle: 'Valor fechado',
  priceLabel: '450 €',
  priceExplanationLabel:
      'É o que pagas no fim, mesmo que o trabalho demore mais.',
  includeLabels: ['Material', 'Remoção de resíduos'],
  facts: [
    ClientProposalFact('Duração', '2 a 3 dias'),
    ClientProposalFact('Válido até', '06/11'),
  ],
  infoLines: [],
  acceptActionLabel: 'Aceitar por 450 €',
);

Widget _detailScreen(
  AsyncValue<ClientProposalDetailViewData?> data, {
  Future<ClientProposalAcceptResult> Function(String)? onAccept,
  VoidCallback? onAccepted,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ClientProposalDetailView(
        dataAsync: data,
        onBack: () {},
        onRetry: () {},
        onOpenWorkerProfile: () {},
        onAccept:
            onAccept ?? (_) async => const ClientProposalAcceptResult.accepted(),
        onAccepted: onAccepted ?? () {},
        onBackToList: () {},
      ),
    ),
  );
}

void main() {
  group('textos e ordem (designs A3 e A6)', () {
    test('ordem: recomendada, avaliação, chegada; expiradas no fim', () {
      final summaries = {
        'wa': (avgRating: 4.2, ratingCount: 5),
        'wb': (avgRating: 4.9, ratingCount: 38),
        'wc': (avgRating: 4.6, ratingCount: 10),
        'wd': (avgRating: 5.0, ratingCount: 50),
      };
      final list = orderProposals([
        _p('a'),
        _p('b'),
        _p('c', mode: ProposalPricingMode.fixedTotal, total: 450),
        _p('d', expired: true),
        _p('e'),
      ], (id) => summaries[id]);
      expect(list.map((p) => p.id), ['b', 'c', 'a', 'e', 'd']);
    });

    test('nunca ordena pelo preço', () {
      final list = orderProposals([
        _p('a', mode: ProposalPricingMode.fixedTotal, total: 900),
        _p('b', rate: 5),
      ], (_) => null);
      expect(list.map((p) => p.id), ['a', 'b']);
    });

    test('expirada nunca é a recomendada', () {
      final summaries = {
        'wa': (avgRating: 5.0, ratingCount: 50),
        'wb': (avgRating: 4.5, ratingCount: 10),
      };
      expect(
        recommendedProposalId(
            [_p('a', expired: true), _p('b')], (id) => summaries[id]),
        'b',
      );
    });

    test('data, avaliações e cabeçalho', () {
      expect(
        proposalScheduleLabel(
          _p('1', date: DateTime(2026, 10, 22), time: '09:00:00'),
          now: DateTime(2026, 10, 19),
        ),
        'Qui, 22/10 · 9:00',
      );
      expect(
          proposalScheduleLabel(_p('1')), 'Data a combinar com o jardineiro');
      expect(proposalRatingLabel((avgRating: 4.9, ratingCount: 38)),
          '4,9 · 38 avaliações');
      expect(proposalRatingLabel((avgRating: 0, ratingCount: 0)), isNull);
      expect(proposalsHeaderSubtitle('Corte de relva', 1),
          'Corte de relva · 1 proposta');
    });
  });

  testWidgets('lista mostra os dois formatos com a caixa "Total"',
      (tester) async {
    await tester.pumpWidget(_list(_loaded([
      _card('Rui Costa', recommended: true, fixed: true),
      _card('João Pires'),
    ])));
    await tester.pumpAndSettle();

    expect(find.text('Corte de relva · 2 propostas'), findsOneWidget);
    expect(find.text('Recomendada'), findsOneWidget);
    expect(find.text('valor fechado'), findsOneWidget);
    expect(find.text('preço por hora'), findsOneWidget);
    expect(find.text('Total'), findsNWidgets(2));
    expect(find.text('Fechado. Não muda com as horas.'), findsOneWidget);
    expect(find.text('Estimado. Depende das horas feitas.'), findsOneWidget);
  });

  testWidgets('expirada aparece marcada e tocar abre o detalhe',
      (tester) async {
    ClientProposalCardViewData? opened;
    await tester.pumpWidget(_list(
      _loaded([_card('Ana Lopes'), _card('Rui Costa', expired: true)]),
      onOpen: (p) => opened = p,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Expirada'), findsOneWidget);

    await tester.tap(find.text('Ana Lopes'));
    await tester.pumpAndSettle();
    expect(opened?.workerName, 'Ana Lopes');
  });

  testWidgets('vazio e erro', (tester) async {
    await tester.pumpWidget(_list(_loaded(const [])));
    await tester.pumpAndSettle();
    expect(find.text('Ainda sem propostas'), findsOneWidget);

    await tester
        .pumpWidget(_list(AsyncError(Exception('x'), StackTrace.empty)));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar as propostas'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });

  testWidgets('detalhe: aceitar só avança depois do servidor',
      (tester) async {
    var accepted = false;
    await tester.pumpWidget(_detailScreen(
      const AsyncData(_detail),
      onAccepted: () => accepted = true,
    ));
    await tester.pumpAndSettle();

    expect(find.text('450 €'), findsWidgets);
    expect(find.text('INCLUI'), findsOneWidget);
    await tester.tap(find.text('Aceitar por 450 €'));
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
  });

  testWidgets('detalhe: expirou ao aceitar mostra o aviso', (tester) async {
    var accepted = false;
    await tester.pumpWidget(_detailScreen(
      const AsyncData(_detail),
      onAccept: (_) async => const ClientProposalAcceptResult.expired(),
      onAccepted: () => accepted = true,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceitar por 450 €'));
    await tester.pumpAndSettle();
    expect(find.textContaining('expirou'), findsWidgets);
    expect(accepted, isFalse);
  });

  testWidgets('detalhe: indisponível volta à lista', (tester) async {
    await tester.pumpWidget(_detailScreen(
      const AsyncData(_detail),
      onAccept: (_) async => const ClientProposalAcceptResult.unavailable(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceitar por 450 €'));
    await tester.pumpAndSettle();
    expect(find.text('Esta proposta já não está disponível'), findsOneWidget);
    expect(find.text('Ver propostas'), findsOneWidget);
  });

  testWidgets('detalhe: erro fica no ecrã', (tester) async {
    await tester.pumpWidget(_detailScreen(
      const AsyncData(_detail),
      onAccept: (_) async =>
          const ClientProposalAcceptResult.failed('Sem ligação.'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceitar por 450 €'));
    await tester.pumpAndSettle();
    expect(find.text('Sem ligação.'), findsOneWidget);
    expect(find.text('Aceitar por 450 €'), findsOneWidget);
  });
}
