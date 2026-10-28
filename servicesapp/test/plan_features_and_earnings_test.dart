import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/widgets/app_plan_badge.dart';
import 'package:servicesapp/features/proposals/data/proposal_model.dart';
import 'package:servicesapp/features/worker/application/worker_earnings.dart';
import 'package:servicesapp/features/worker/application/worker_plan_features.dart';
import 'package:servicesapp/features/worker/data/worker_earnings_model.dart';
import 'package:servicesapp/features/worker/data/worker_public_card_model.dart';
import 'package:servicesapp/features/worker/presentation/widgets/worker_earnings_view.dart';
import 'package:servicesapp/features/worker/presentation/widgets/worker_share_card_view.dart';

WorkerEarningEntry _entry({
  bool asHelper = false,
  DateTime? doneOn,
  bool awaiting = false,
  ProposalPricingMode mode = ProposalPricingMode.hourly,
  double rate = 20,
  double? total,
  int? minutes,
  double? hMin,
  double? hMax,
  double? helpersCost,
}) =>
    WorkerEarningEntry(
      jobId: 'j',
      asHelper: asHelper,
      serviceName: 'Corte de relva',
      doneOn: doneOn ?? DateTime(2026, 10, 28),
      awaitingConfirmation: awaiting,
      pricingMode: mode,
      rate: rate,
      totalPrice: total,
      workedMinutes: minutes,
      estimatedHoursMin: hMin,
      estimatedHoursMax: hMax,
      helpersCost: helpersCost,
    );

void main() {
  group('o que cada plano dá', () {
    test('Grátis não tem PDF, ganhos, selo nem Benefícios', () {
      const t = WorkerPlanTier.free;
      expect(t.canExportCardPdf, isFalse);
      expect(t.hasEarnings, isFalse);
      expect(t.hasBadge, isFalse);
      expect(t.hasPartnerBenefits, isFalse);
      expect(t.hasUnlimitedJobs, isFalse);
    });

    test('Pro tem PDF e ganhos, mas os Benefícios são só do Pro+', () {
      expect(WorkerPlanTier.pro.canExportCardPdf, isTrue);
      expect(WorkerPlanTier.pro.hasEarnings, isTrue);
      expect(WorkerPlanTier.pro.hasPartnerBenefits, isFalse);
      expect(WorkerPlanTier.proPlus.hasPartnerBenefits, isTrue);
      expect(WorkerPlanTier.proPlus.hasEarnings, isTrue);
    });

    test('a tabela usa o limite do servidor e bate com as regras', () {
      final rows = workerPlanFeatureRows(freeMonthlyLimit: 7);
      expect(rows.first.free, '7/mês');
      final pdf = rows.firstWhere((r) => r.label == 'Cartão em PDF');
      expect(pdf.valueFor(WorkerPlanTier.free), planNotIncluded);
      expect(pdf.valueFor(WorkerPlanTier.pro), planIncluded);
      final benefits = rows.firstWhere((r) => r.label.startsWith('Benefícios'));
      expect(benefits.valueFor(WorkerPlanTier.pro), planNotIncluded);
      expect(benefits.valueFor(WorkerPlanTier.proPlus), planIncluded);
    });
  });

  group('plano nas leituras do servidor', () {
    test('cartão público e proposta leem o plano, e sem coluna é Grátis', () {
      final card = WorkerPublicCard.fromJson({
        'worker_id': 'w',
        'plan_tier': 'pro_plus',
      });
      expect(card.planTier, WorkerPlanTier.proPlus);
      expect(
        WorkerPublicCard.fromJson({'worker_id': 'w'}).planTier,
        WorkerPlanTier.free,
      );
      final proposal = JobProposal.fromJson({
        'id': 'p',
        'job_id': 'j',
        'worker_id': 'w',
        'hourly_rate': 20,
        'people_needed': 1,
        'status': 'pending',
        'created_at': '2026-10-28T10:00:00Z',
        'worker_plan_tier': 'pro',
      });
      expect(proposal.workerPlanTier, WorkerPlanTier.pro);
    });
  });

  group('ganhos', () {
    test('por hora usa as horas registadas', () {
      final a = earningAmount(_entry(rate: 20, minutes: 150));
      expect(a.amount, 50);
      expect(a.estimated, isFalse);
    });

    test('sem horas registadas usa a média da estimativa e marca-a', () {
      final a = earningAmount(_entry(rate: 20, hMin: 2, hMax: 4));
      expect(a.amount, 60);
      expect(a.estimated, isTrue);
      expect(earningAmountLabel(_entry(rate: 20, hMin: 2, hMax: 4)),
          '≈ 60,00 €');
    });

    test('valor fechado desconta os ajudantes e nunca fica negativo', () {
      expect(
        earningAmount(_entry(
          mode: ProposalPricingMode.fixedTotal,
          total: 150,
          helpersCost: 28,
        )).amount,
        122,
      );
      expect(
        earningAmount(_entry(
          mode: ProposalPricingMode.fixedTotal,
          total: 10,
          helpersCost: 28,
        )).amount,
        0,
      );
    });

    test('ajudante recebe o valor acordado pelas horas', () {
      final e = _entry(asHelper: true, rate: 14, minutes: 120);
      expect(earningAmount(e).amount, 28);
      expect(earningEntrySubtitle(e), '28/10 · Ajudante · 2 h');
    });

    test('agrupa por mês com zeros e separa o que está por confirmar', () {
      final months = groupEarningsByMonth(
        [
          _entry(minutes: 60, doneOn: DateTime(2026, 10, 2)),
          _entry(minutes: 90, doneOn: DateTime(2026, 10, 20), awaiting: true),
          _entry(minutes: 60, doneOn: DateTime(2026, 8, 5)),
        ],
        lastMonth: DateTime(2026, 10, 28),
        months: 3,
      );
      expect(months.map((m) => m.month.month), [8, 9, 10]);
      expect(months[1].jobCount, 0);
      final oct = months.last;
      expect(oct.total, 50);
      expect(oct.awaitingTotal, 30);
      expect(oct.registeredHours, 2.5);
      expect(oct.entries.first.doneOn.day, 20);
    });

    test('rótulos de mês e de horas', () {
      expect(earningsMonthLabel(DateTime(2026, 10)), 'Outubro 2026');
      expect(earningsMonthShortLabel(DateTime(2026, 3)), 'Mar');
      expect(earningsHoursLabel(2.5), '2 h 30');
      expect(earningsHoursLabel(0.75), '45 min');
      expect(earningsHoursLabel(0), '—');
    });

    test('lê a linha da RPC', () {
      final e = WorkerEarningEntry.fromJson({
        'job_id': 'j',
        'role': 'helper',
        'service_type_name': 'Poda',
        'done_on': '2026-10-28',
        'job_status': 'awaiting_confirmation',
        'pricing_mode': 'hourly',
        'rate': 14,
        'worked_minutes': 120,
      });
      expect(e.asHelper, isTrue);
      expect(e.awaitingConfirmation, isTrue);
      expect(e.workedMinutes, 120);
    });
  });

  group('ecrãs', () {
    Widget wrap(Widget child) => MaterialApp(home: child);

    testWidgets('selo não aparece no Grátis', (tester) async {
      await tester.pumpWidget(wrap(const Scaffold(
        body: Column(children: [
          AppPlanBadge(tier: WorkerPlanTier.free),
          AppPlanBadge(tier: WorkerPlanTier.proPlus),
        ]),
      )));
      expect(find.text('Pro+'), findsOneWidget);
      expect(find.text('Grátis'), findsNothing);
    });

    testWidgets('ganhos no Grátis mostra o convite', (tester) async {
      await tester.pumpWidget(wrap(WorkerEarningsView(
        locked: true,
        monthsAsync: const AsyncValue.data([]),
        onBack: () {},
        onOpenPlans: () {},
        onRetry: () {},
        onRefresh: () async {},
      )));
      await tester.pumpAndSettle();
      expect(find.text('Painel de ganhos no Pro'), findsOneWidget);
      expect(find.text('Ver planos'), findsOneWidget);
    });

    testWidgets('ganhos no Pro mostra o total do mês e navega', (tester) async {
      final months = groupEarningsByMonth(
        [
          _entry(minutes: 120, doneOn: DateTime(2026, 10, 2)),
          _entry(minutes: 60, doneOn: DateTime(2026, 9, 2)),
        ],
        lastMonth: DateTime(2026, 10),
        months: 12,
      );
      await tester.pumpWidget(wrap(WorkerEarningsView(
        locked: false,
        monthsAsync: AsyncValue.data(months),
        onBack: () {},
        onOpenPlans: () {},
        onRetry: () {},
        onRefresh: () async {},
      )));
      await tester.pumpAndSettle();
      expect(find.text('Outubro 2026'), findsOneWidget);
      expect(find.text('40,00 €'), findsWidgets);
      await tester.tap(find.byTooltip('Mês anterior'));
      await tester.pumpAndSettle();
      expect(find.text('Setembro 2026'), findsOneWidget);
      expect(find.text('20,00 €'), findsWidgets);
    });

    testWidgets('cartão partilhável mostra QR, selo e PDF bloqueado no Grátis',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      var pdfTaps = 0;
      await tester.pumpWidget(wrap(WorkerShareCardView(
        data: const WorkerShareCardViewData(
          name: 'Rui Costa',
          professionLocationLabel: 'Corte de relva · Braga',
          ratingLabel: '4,9 · 12 avaliações',
          qrUrl: 'https://projardim.pt/w/abc?src=qr',
          displayUrl: 'projardim.pt/w/abc',
          planTier: WorkerPlanTier.free,
          canExportPdf: false,
        ),
        cardKey: GlobalKey(),
        busy: false,
        onBack: () {},
        onShareImage: () {},
        onSavePdf: () => pdfTaps++,
        onSendLink: () {},
        onCopyLink: () {},
      )));
      await tester.pumpAndSettle();
      expect(find.text('Rui Costa'), findsOneWidget);
      expect(find.text('Pede-me um orçamento'), findsOneWidget);
      expect(find.text('Partilhar cartão'), findsOneWidget);
      // O selo "Pro" aparece no botão do PDF (é preciso o Pro), não no nome.
      expect(find.text('Pro'), findsOneWidget);
      await tester.tap(find.text('Guardar PDF'));
      expect(pdfTaps, 1);
    });
  });
}
