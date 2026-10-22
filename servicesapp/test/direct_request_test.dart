import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/client/application/client_create_job_wizard_provider.dart';
import 'package:servicesapp/features/client/application/job_request_form.dart';
import 'package:servicesapp/features/client/presentation/widgets/direct_request_waiting_banner.dart';
import 'package:servicesapp/features/client/presentation/widgets/repeat_hire_card.dart';
import 'package:servicesapp/features/client/presentation/widgets/your_gardeners_section.dart';
import 'package:servicesapp/features/jobs/application/client_job_next_step.dart';
import 'package:servicesapp/features/jobs/application/direct_request_labels.dart';
import 'package:servicesapp/features/jobs/data/direct_request_models.dart';
import 'package:servicesapp/features/jobs/data/job_model.dart';
import 'package:servicesapp/features/worker/presentation/widgets/worker_direct_request_card.dart';

// Pedido direto ("Pedir de novo", design A5, migration 0057).

JobRequest _job({
  JobStatus status = JobStatus.open,
  DirectRequestStatus? direct,
  int proposals = 0,
  DateMode dateMode = DateMode.fixed,
  DateTime? preferredDate,
}) =>
    JobRequest(
      id: 'job-1',
      clientId: 'client',
      serviceTypeId: 'relva',
      addressText: 'Rua das Flores 12, Braga',
      locationArea: 'Braga',
      locationLat: 41.55,
      locationLng: -8.42,
      dateMode: dateMode,
      preferredDate: preferredDate,
      urgency: Urgency.urgent,
      sizeEstimate: SizeEstimate.medium,
      description: 'Relva das traseiras, cerca de 200 m2.',
      status: status,
      proposalCount: proposals,
      expiresAt: DateTime(2026, 12, 1),
      createdAt: DateTime(2026, 10, 1),
      directWorkerId: direct == null ? null : 'rui',
      directUntil: direct == null ? null : DateTime(2026, 10, 23, 14, 30),
      directStatus: direct,
    );

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('labels', () {
    test('primeiro nome e inicial', () {
      expect(firstNameOr('Rui Costa', 'x'), 'Rui');
      expect(firstNameOr('  ', 'o jardineiro'), 'o jardineiro');
      expect(initialOf('ana'), 'A');
      expect(initialOf(''), '');
    });

    test('cartão só com 4 ou 5 estrelas, ou sem avaliação', () {
      RepeatHireInfo info(int? stars) => RepeatHireInfo(
            workerId: 'w',
            workerName: 'Rui',
            workerAvatarUrl: '',
            serviceTypeId: 's',
            jobDate: null,
            canRequest: true,
            myStars: stars,
          );
      expect(showRepeatHire(info(null)), isTrue);
      expect(showRepeatHire(info(4)), isTrue);
      expect(showRepeatHire(info(5)), isTrue);
      expect(showRepeatHire(info(3)), isFalse);
      expect(showRepeatHire(info(1)), isFalse);
    });

    test('tempo que falta na etiqueta do jardineiro', () {
      final now = DateTime(2026, 10, 22, 20);
      expect(directTimeLeftLabel(now.add(const Duration(hours: 18, minutes: 10)), now),
          'faltam 18 h');
      expect(directTimeLeftLabel(now.add(const Duration(minutes: 70)), now), 'falta 1 h');
      expect(directTimeLeftLabel(now.add(const Duration(minutes: 20)), now),
          'falta menos de 1 h');
      expect(directTimeLeftLabel(now.subtract(const Duration(minutes: 5)), now),
          'falta menos de 1 h');
    });

    test('há quanto tempo', () {
      final now = DateTime(2026, 10, 22, 9);
      expect(timeAgoLabel(DateTime(2026, 10, 22), now), 'hoje');
      expect(timeAgoLabel(DateTime(2026, 10, 21), now), 'ontem');
      expect(timeAgoLabel(DateTime(2026, 10, 18), now), 'há 4 dias');
      expect(timeAgoLabel(DateTime(2026, 10, 1), now), 'há 3 semanas');
      expect(timeAgoLabel(DateTime(2026, 8, 20), now), 'há 2 meses');
      expect(timeAgoLabel(DateTime(2025, 9, 1), now), 'há 1 ano');
    });

    test('faixa do pedido aberto segue o estado do servidor', () {
      expect(directBannerTexts(_job(), workerName: 'Rui'), isNull);
      expect(
        directBannerTexts(
          _job(status: JobStatus.confirmed, direct: DirectRequestStatus.waiting),
          workerName: 'Rui',
        ),
        isNull,
      );
      expect(
        directBannerTexts(_job(direct: DirectRequestStatus.released), workerName: 'Rui'),
        isNull,
      );

      final waiting = directBannerTexts(
        _job(direct: DirectRequestStatus.waiting),
        workerName: 'Rui Costa',
      )!;
      expect(waiting.kind, DirectBannerKind.waiting);
      expect(waiting.title, startsWith('À espera de Rui até '));
      expect(waiting.description, 'Por agora só Rui vê o pedido.');

      final proposed = directBannerTexts(
        _job(direct: DirectRequestStatus.waiting, proposals: 1),
        workerName: 'Rui',
      )!;
      expect(proposed.description, startsWith('Rui já enviou proposta.'));

      final declined = directBannerTexts(
        _job(direct: DirectRequestStatus.declined),
        workerName: 'Rui',
      )!;
      expect(declined.kind, DirectBannerKind.released);
      expect(declined.title, 'Rui não pode desta vez');

      expect(
        directBannerTexts(_job(direct: DirectRequestStatus.expired), workerName: 'Rui')!
            .title,
        'Rui não respondeu a tempo',
      );
      expect(
        directBannerTexts(_job(direct: DirectRequestStatus.expired), workerName: '')!
            .title,
        'O jardineiro não respondeu a tempo',
      );
    });

    test('histórico com o cliente', () {
      final ctx = DirectRequestContext(
        clientName: 'Marta Silva',
        jobDate: DateTime(2026, 9, 12),
        serviceTypeId: 's',
        hourlyRate: 12,
      );
      expect(
        directHistoryLabel(ctx, serviceLabel: 'Corte de relva'),
        'Já trabalhaste com Marta a 12/09/2026, Corte de relva, 12,00 €/h.',
      );
      expect(
        directHistoryLabel(
          const DirectRequestContext(
            clientName: '',
            jobDate: null,
            serviceTypeId: 's',
            hourlyRate: null,
          ),
          serviceLabel: '',
        ),
        'Já trabalhaste com este cliente.',
      );
    });
  });

  group('dados', () {
    test('JobRequest lê os campos do pedido direto', () {
      final job = JobRequest.fromJson({
        'id': 'j',
        'client_id': 'c',
        'service_type_id': 's',
        'location_lat': 1,
        'location_lng': 2,
        'description': 'd',
        'status': 'open',
        'expires_at': '2026-10-24T10:00:00Z',
        'created_at': '2026-10-22T10:00:00Z',
        'direct_worker_id': 'w',
        'direct_source_job_id': 'old',
        'direct_until': '2026-10-23T10:00:00Z',
        'direct_status': 'waiting',
      });
      expect(job.isDirectWaiting, isTrue);
      expect(job.directWorkerId, 'w');
      expect(job.directSourceJobId, 'old');
      expect(job.directUntil, DateTime.utc(2026, 10, 23, 10));

      final normal = JobRequest.fromJson({
        'id': 'j',
        'client_id': 'c',
        'service_type_id': 's',
        'location_lat': 1,
        'location_lng': 2,
        'description': 'd',
        'status': 'open',
        'expires_at': '2026-10-24T10:00:00Z',
        'created_at': '2026-10-22T10:00:00Z',
      });
      expect(normal.directStatus, isNull);
      expect(normal.isDirectWaiting, isFalse);
    });

    test('rascunho de "Pedir de novo": mesmos dados, sem data, com o jardineiro', () {
      final draft = repeatHireWizardState(
        _job(
          status: JobStatus.completed,
          preferredDate: DateTime(2026, 12, 20),
        ),
        workerName: 'Rui Costa',
        now: DateTime(2026, 10, 22),
      );
      expect(draft.serviceTypeId, 'relva');
      expect(draft.addressText, 'Rua das Flores 12, Braga');
      expect(draft.description, 'Relva das traseiras, cerca de 200 m2.');
      expect(draft.sizeEstimate, SizeEstimate.medium);
      expect(draft.preferredDate, isNull);
      expect(draft.urgency, Urgency.normal);
      expect(draft.directSourceJobId, 'job-1');
      expect(draft.directWorkerName, 'Rui Costa');
      expect(draft.isDirectRequest, isTrue);
      expect(repeatHireFirstRoute(draft), '/client/create-job/schedule');

      // Mudar o agendamento não perde o jardineiro.
      final copy = draft.copyWith(description: 'outra descrição longa');
      expect(copy.directSourceJobId, 'job-1');

      final normal = draft.withoutDirectWorker();
      expect(normal.isDirectRequest, isFalse);
      expect(normal.directWorkerName, '');
      expect(normal.description, draft.description);
    });

    test('serviço que saiu do catálogo leva ao primeiro passo', () {
      final draft = repeatHireWizardState(
        _job(status: JobStatus.completed),
        workerName: 'Rui',
        now: DateTime(2026, 10, 22),
        serviceStillOffered: false,
      );
      expect(repeatHireFirstRoute(draft), '/client/create-job');
    });

    test('próximo passo do pedido à espera do jardineiro escolhido', () {
      expect(
        clientJobNextStepLabel(_job(direct: DirectRequestStatus.waiting)),
        startsWith('Só o teu jardineiro vê o pedido até '),
      );
      expect(
        clientJobNextStepLabel(_job(direct: DirectRequestStatus.waiting, proposals: 1)),
        'Tens 1 proposta para ver.',
      );
      expect(
        clientJobNextStepLabel(_job(direct: DirectRequestStatus.expired)),
        'À espera de propostas dos jardineiros.',
      );
    });

    test('a notificação de nova data não toca no estado do rascunho normal', () {
      const empty = ClientCreateJobWizardState();
      expect(empty.isDirectRequest, isFalse);
      expect(empty.withoutDirectWorker().isDirectRequest, isFalse);
    });
  });

  group('widgets', () {
    testWidgets('"Os teus jardineiros" vazio não mostra nada', (tester) async {
      await tester.pumpWidget(_app(YourGardenersSection(
        dataAsync: const AsyncValue.data([]),
        onRepeatHire: (_) {},
      )));
      expect(find.text(YourGardenersSection.title), findsNothing);
    });

    testWidgets('"Os teus jardineiros" com dados e toque', (tester) async {
      YourGardenerCardViewData? tapped;
      await tester.pumpWidget(_app(YourGardenersSection(
        dataAsync: const AsyncValue.data([
          YourGardenerCardViewData(
            workerId: 'rui',
            workerName: 'Rui',
            workerInitial: 'R',
            lastServiceLabel: 'Corte de relva',
            lastWorkedLabel: 'há 3 semanas',
          ),
          YourGardenerCardViewData(
            workerId: 'ana',
            workerName: 'Ana',
            workerInitial: 'A',
            lastServiceLabel: 'Poda de sebes',
            lastWorkedLabel: 'há 2 meses',
          ),
        ]),
        onRepeatHire: (card) => tapped = card,
      )));
      await tester.pumpAndSettle();
      expect(find.text(YourGardenersSection.title), findsOneWidget);
      expect(find.text('Rui'), findsOneWidget);
      expect(find.text('há 2 meses'), findsOneWidget);
      await tester.tap(find.text('Ana'));
      expect(tapped?.workerId, 'ana');
    });

    testWidgets('"Os teus jardineiros" com erro mantém o título e tenta de novo',
        (tester) async {
      var retried = false;
      await tester.pumpWidget(_app(YourGardenersSection(
        dataAsync: AsyncValue.error(Exception('x'), StackTrace.empty),
        onRepeatHire: (_) {},
        onRetry: () => retried = true,
      )));
      expect(find.text(YourGardenersSection.title), findsOneWidget);
      await tester.tap(find.text('Tentar novamente'));
      expect(retried, isTrue);
    });

    testWidgets('cartão "Precisas outra vez?" some sem dados', (tester) async {
      await tester.pumpWidget(_app(const RepeatHireCard(
        dataAsync: AsyncValue.data(null),
      )));
      expect(find.text('Precisas outra vez?'), findsNothing);

      await tester.pumpWidget(_app(const RepeatHireCard(
        dataAsync: AsyncValue.data(RepeatHireCardViewData(
          workerName: 'Rui',
          previousJobLabel: 'Corte de relva, 12/10/2026',
          descriptionLabel: 'Pede de novo.',
        )),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Precisas outra vez?'), findsOneWidget);
      expect(find.text('Corte de relva, 12/10/2026'), findsOneWidget);
    });

    testWidgets('"Mostrar já a todos": erro fica dentro da faixa', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_app(DirectRequestWaitingBanner(
        data: const DirectRequestWaitingBannerViewData(
          display: DirectRequestWaitingDisplay.waiting,
          titleLabel: 'À espera de Rui até 23/10 às 14:30',
          descriptionLabel: 'Por agora só Rui vê o pedido.',
          workerInitial: 'R',
          releaseActionLabel: 'Mostrar já a todos',
        ),
        onReleaseToAll: () async {
          calls++;
          return 'Sem ligação.';
        },
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mostrar já a todos'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Sem ligação.'), findsOneWidget);
      expect(find.text('Mostrar já a todos'), findsOneWidget);
    });

    testWidgets('faixa depois de abrir a todos não tem botão', (tester) async {
      await tester.pumpWidget(_app(DirectRequestWaitingBanner(
        data: const DirectRequestWaitingBannerViewData(
          display: DirectRequestWaitingDisplay.released,
          titleLabel: 'Rui não pode desta vez',
          descriptionLabel: 'O pedido já está visível para todos os jardineiros.',
        ),
        onReleaseToAll: () async => null,
      )));
      await tester.pumpAndSettle();
      expect(find.text('Rui não pode desta vez'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('jardineiro: a avisar bloqueia os dois botões', (tester) async {
      await tester.pumpWidget(_app(WorkerDirectRequestActions(
        onSendProposalPressed: () {},
        onDeclinePressed: () {},
        declining: true,
      )));
      expect(find.text('A avisar...'), findsOneWidget);
      final outlined = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(outlined.onPressed, isNull);
    });

    testWidgets('jardineiro: histórico a carregar, com erro e vazio', (tester) async {
      WorkerDirectRequestViewData data(
        AsyncValue<WorkerDirectHistoryViewData?> history,
      ) =>
          WorkerDirectRequestViewData(
            tagLabel: 'Pedido só para ti · faltam 18 h',
            explanationLabel: 'O cliente pediu-te este trabalho primeiro.',
            history: history,
          );

      await tester.pumpWidget(_app(WorkerDirectRequestCard(
        data: data(const AsyncValue.data(WorkerDirectHistoryViewData(
          clientInitial: 'M',
          label: 'Já trabalhaste com Marta a 12/09/2026.',
        ))),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Pedido só para ti · faltam 18 h'), findsOneWidget);
      expect(find.text('Já trabalhaste com Marta a 12/09/2026.'), findsOneWidget);

      var retried = false;
      await tester.pumpWidget(_app(WorkerDirectRequestCard(
        data: data(AsyncValue.error(Exception('x'), StackTrace.empty)),
        onRetryHistory: () => retried = true,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tentar novamente'));
      expect(retried, isTrue);

      await tester.pumpWidget(_app(WorkerDirectRequestCard(
        data: data(const AsyncValue.data(null)),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Tentar novamente'), findsNothing);
      expect(find.text('O cliente pediu-te este trabalho primeiro.'), findsOneWidget);
    });
  });
}
