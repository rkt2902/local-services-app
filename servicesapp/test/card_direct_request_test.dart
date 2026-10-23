import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/models/worker_public_card_feature_access.dart';
import 'package:servicesapp/core/widgets/app_screen_loading_skeleton.dart';
import 'package:servicesapp/features/auth/application/direct_request_auth_context.dart';
import 'package:servicesapp/features/auth/presentation/widgets/direct_request_auth_banner.dart';
import 'package:servicesapp/features/client/application/client_create_job_wizard_provider.dart';
import 'package:servicesapp/features/client/application/job_request_form.dart';
import 'package:servicesapp/features/client/presentation/widgets/direct_request_create_header.dart';
import 'package:servicesapp/features/client/presentation/widgets/direct_request_review_banner.dart';
import 'package:servicesapp/features/client/presentation/widgets/direct_request_services_state.dart';
import 'package:servicesapp/features/client/presentation/widgets/direct_request_waiting_banner.dart';
import 'package:servicesapp/features/jobs/application/client_job_next_step.dart';
import 'package:servicesapp/features/jobs/application/direct_request_labels.dart';
import 'package:servicesapp/features/jobs/data/job_model.dart';
import 'package:servicesapp/features/worker/data/worker_public_card_model.dart';
import 'package:servicesapp/features/worker/presentation/widgets/worker_direct_request_card.dart';
import 'package:servicesapp/features/worker/presentation/widgets/worker_public_card_view.dart';

// Pedido direto pelo cartão público (design A7, migration 0059).

JobRequest _job({
  DirectRequestStatus? direct,
  String? holdReason,
  bool autoRelease = true,
  int proposals = 0,
}) =>
    JobRequest(
      id: 'job-1',
      clientId: 'client',
      serviceTypeId: 'relva',
      addressText: 'Rua das Flores 12, Braga',
      locationArea: 'Braga',
      locationLat: 41.55,
      locationLng: -8.42,
      dateMode: DateMode.flexible,
      urgency: Urgency.normal,
      sizeEstimate: SizeEstimate.medium,
      description: 'Relva das traseiras, cerca de 200 m2.',
      status: JobStatus.open,
      proposalCount: proposals,
      expiresAt: DateTime(2026, 12, 1),
      createdAt: DateTime(2026, 10, 1),
      directWorkerId: direct == null ? null : 'rui',
      directUntil: direct == null ? null : DateTime(2026, 10, 23, 14, 30),
      directStatus: direct,
      directOrigin: direct == null ? null : DirectRequestOrigin.publicCard,
      directAutoRelease: autoRelease,
      directHoldReason: holdReason,
    );

const _card = WorkerPublicCard(
  workerId: 'rui',
  fullName: 'Rui Costa',
  locationName: 'Braga',
  serviceNames: ['Corte de relva'],
  avgRating: 4.8,
  ratingCount: 12,
  serviceTypeIds: ['relva'],
  latestReviewComment: 'Muito cuidadoso.',
  latestReviewAuthor: 'Marta',
);

WorkerPublicCardViewData _data({
  WorkerPublicCardViewerMode mode = WorkerPublicCardViewerMode.clientSignedIn,
  WorkerPublicCardFeatureAccess access =
      const WorkerPublicCardFeatureAccess.allEnabled(),
  String? review,
}) =>
    WorkerPublicCardViewData(
      card: _card,
      featureAccess: access,
      viewerMode: mode,
      directRequestActionLabel: cardDirectRequestActionLabel(_card.fullName),
      latestReviewLabel: review,
    );

class _Calls {
  final started = <String>[];
  final shared = <String>[];
  var logins = 0;
  var retries = 0;
  var generic = 0;
}

Widget _cardApp(
  AsyncValue<WorkerPublicCardViewData?> dataAsync,
  _Calls calls, {
  bool withGeneric = true,
}) =>
    MaterialApp(
      home: WorkerPublicCardView(
        dataAsync: dataAsync,
        onBack: () {},
        onStartDirectRequest: calls.started.add,
        onShareCard: calls.shared.add,
        onLogin: () => calls.logins++,
        onRetry: () => calls.retries++,
        onCreateGenericRequest: withGeneric ? () => calls.generic++ : null,
      ),
    );

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('flags do cartão', () {
    test('hoje está tudo ligado para todos', () {
      const access = WorkerPublicCardFeatureAccess.allEnabled();
      expect(access.canUsePublicCard, isTrue);
      expect(access.canSharePublicCard, isTrue);
      expect(access.canReceiveDirectRequests, isTrue);
    });

    test('o modelo do cartão conta como ligado sem as colunas da 0059', () {
      final card = WorkerPublicCard.fromJson({
        'worker_id': 'rui',
        'full_name': 'Rui',
        'location_name': 'Braga',
        'service_names': <String>[],
        'avg_rating': 0,
        'rating_count': 0,
      });
      expect(card.canUsePublicCard, isTrue);
      expect(card.canReceiveDirectRequests, isTrue);
      expect(card.serviceTypeIds, isEmpty);
    });
  });

  group('cartão público', () {
    testWidgets('cliente com sessão: só "Pedir orçamento a Rui"',
        (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(_cardApp(AsyncValue.data(_data()), calls));
      await tester.pumpAndSettle();

      expect(find.text('Pedir orçamento a Rui'), findsOneWidget);
      expect(find.text('Já tens conta? Entra'), findsNothing);
      expect(find.text('Partilhar cartão'), findsNothing);
      await tester.tap(find.text('Pedir orçamento a Rui'));
      expect(calls.started, ['rui']);
    });

    testWidgets('sem sessão: pedir e "Já tens conta? Entra"', (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(_cardApp(
        AsyncValue.data(_data(mode: WorkerPublicCardViewerMode.signedOut)),
        calls,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Pedir orçamento a Rui'), findsOneWidget);
      await tester.tap(find.text('Já tens conta? Entra'));
      expect(calls.logins, 1);
    });

    testWidgets('outro jardineiro: sem barra de ações', (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(_cardApp(
        AsyncValue.data(_data(mode: WorkerPublicCardViewerMode.anotherWorker)),
        calls,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Pedir orçamento a Rui'), findsNothing);
      expect(find.text('Partilhar cartão'), findsNothing);
      expect(find.text('Rui Costa'), findsOneWidget);
    });

    testWidgets('o próprio: pré-visualização e "Partilhar cartão"',
        (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(_cardApp(
        AsyncValue.data(_data(mode: WorkerPublicCardViewerMode.ownerPreview)),
        calls,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Pré-visualização'), findsOneWidget);
      expect(find.text('Pedir orçamento a Rui'), findsNothing);
      await tester.tap(find.text('Partilhar cartão'));
      expect(calls.shared, ['rui']);
    });

    testWidgets('sem pedidos diretos não há botão de pedir', (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(_cardApp(
        AsyncValue.data(_data(
          mode: WorkerPublicCardViewerMode.signedOut,
          access: const WorkerPublicCardFeatureAccess(
            canUsePublicCard: true,
            canSharePublicCard: true,
            canReceiveDirectRequests: false,
          ),
        )),
        calls,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Pedir orçamento a Rui'), findsNothing);
      expect(find.text('Já tens conta? Entra'), findsNothing);
      expect(find.text('Rui Costa'), findsOneWidget);
    });

    testWidgets('sem partilha o próprio não tem botão', (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(_cardApp(
        AsyncValue.data(_data(
          mode: WorkerPublicCardViewerMode.ownerPreview,
          access: const WorkerPublicCardFeatureAccess(
            canUsePublicCard: true,
            canSharePublicCard: false,
            canReceiveDirectRequests: true,
          ),
        )),
        calls,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Partilhar cartão'), findsNothing);
    });

    testWidgets('cartão desligado: indisponível com pedido para todos',
        (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(_cardApp(
        AsyncValue.data(_data(
          access: const WorkerPublicCardFeatureAccess(
            canUsePublicCard: false,
            canSharePublicCard: false,
            canReceiveDirectRequests: false,
          ),
        )),
        calls,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Este cartão já não está disponível'), findsOneWidget);
      expect(find.text('Rui Costa'), findsNothing);
      await tester.tap(find.text('Criar pedido para todos'));
      expect(calls.generic, 1);
    });

    testWidgets('cartão que não existe fica igual, sem botão para jardineiro',
        (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(
        _cardApp(const AsyncValue.data(null), calls, withGeneric: false),
      );
      await tester.pumpAndSettle();

      expect(find.text('Este cartão já não está disponível'), findsOneWidget);
      expect(find.text('Criar pedido para todos'), findsNothing);
    });

    testWidgets('a carregar mostra o esqueleto', (tester) async {
      await tester.pumpWidget(_cardApp(const AsyncValue.loading(), _Calls()));
      await tester.pump();

      expect(find.byType(AppScreenLoadingSkeleton), findsOneWidget);
      expect(find.text('Pedir orçamento a Rui'), findsNothing);
    });

    testWidgets('erro com "Tentar novamente"', (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(_cardApp(
        AsyncValue.error(Exception('rede'), StackTrace.empty),
        calls,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Não foi possível abrir o cartão'), findsOneWidget);
      await tester.tap(find.text('Tentar novamente'));
      expect(calls.retries, 1);
    });

    testWidgets('sem foto mostra as iniciais; avaliação recente opcional',
        (tester) async {
      await tester.pumpWidget(_cardApp(
        AsyncValue.data(_data(review: '"Muito cuidadoso." · Marta')),
        _Calls(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('RC'), findsOneWidget);
      expect(find.text('"Muito cuidadoso." · Marta'), findsOneWidget);

      await tester.pumpWidget(_cardApp(AsyncValue.data(_data()), _Calls()));
      await tester.pumpAndSettle();
      expect(find.text('AVALIAÇÃO RECENTE'), findsNothing);
    });

    test('iniciais do nome', () {
      expect(nameInitials('Rui Costa Santos'), 'RS');
      expect(nameInitials('rui'), 'R');
      expect(nameInitials('  '), '');
    });
  });

  group('voltar ao pedido depois de entrar', () {
    test('guarda e lê o jardineiro e a visita', () {
      final saved = DirectRequestAuthContext(
        workerId: 'rui',
        workerName: 'Rui Costa',
        visitId: 'visit-1',
        savedAt: DateTime.utc(2026, 10, 22, 10),
      );
      final read = DirectRequestAuthContext.fromJson(saved.toJson())!;
      expect(read.workerId, 'rui');
      expect(read.workerName, 'Rui Costa');
      expect(read.visitId, 'visit-1');
      expect(read.savedAt, saved.savedAt);
    });

    test('dados estragados não voltam a lado nenhum', () {
      expect(DirectRequestAuthContext.fromJson({'worker_name': 'Rui'}), isNull);
    });

    test('passado um dia já não volta sozinho', () {
      final saved = DirectRequestAuthContext(
        workerId: 'rui',
        workerName: 'Rui',
        savedAt: DateTime(2026, 10, 22, 10),
      );
      expect(saved.isFresh(DateTime(2026, 10, 22, 20)), isTrue);
      expect(saved.isFresh(DateTime(2026, 10, 23, 11)), isFalse);
    });

    testWidgets('faixa do registo', (tester) async {
      await tester.pumpWidget(_app(const DirectRequestAuthBanner(
        workerName: 'Rui Costa',
        descriptionLabel: 'Cria a conta e voltas logo ao pedido.',
      )));

      expect(find.text('Vais pedir orçamento a Rui'), findsOneWidget);
      expect(find.text('Cria a conta e voltas logo ao pedido.'), findsOneWidget);
    });
  });

  group('wizard do pedido pelo cartão', () {
    test('mantém a morada, o serviço fica por escolher', () {
      const current = ClientCreateJobWizardState(
        serviceTypeId: 'sebes',
        addressText: 'Rua das Flores 12',
        locationLat: 41.55,
        locationLng: -8.42,
        description: 'Relva grande',
        directSourceJobId: 'antigo',
      );
      final draft = cardRequestWizardState(
        current,
        workerId: 'rui',
        workerName: 'Rui Costa',
        visitId: 'visit-1',
      );
      expect(draft.serviceTypeId, isNull);
      expect(draft.addressText, 'Rua das Flores 12');
      expect(draft.description, 'Relva grande');
      expect(draft.directSourceJobId, isNull);
      expect(draft.directCardWorkerId, 'rui');
      expect(draft.cardVisitId, 'visit-1');
      expect(draft.directAutoRelease, isTrue);
      expect(draft.isCardRequest, isTrue);
      expect(draft.isDirectRequest, isTrue);
      expect(wizardFirstIncompleteRoute(draft), '/client/create-job');
    });

    test('o interruptor e "Ver todos" passam pelos outros passos', () {
      final draft = cardRequestWizardState(
        const ClientCreateJobWizardState(),
        workerId: 'rui',
        workerName: 'Rui',
      ).copyWith(directAutoRelease: false, directShowAllServices: true);
      final next = draft.copyWith(serviceTypeId: 'relva');
      expect(next.directCardWorkerId, 'rui');
      expect(next.directAutoRelease, isFalse);
      expect(next.directShowAllServices, isTrue);
    });

    test('"Criar pedido" normal tira o jardineiro', () {
      final draft = cardRequestWizardState(
        const ClientCreateJobWizardState(),
        workerId: 'rui',
        workerName: 'Rui',
      ).withoutDirectWorker();
      expect(draft.isDirectRequest, isFalse);
      expect(draft.directAutoRelease, isTrue);
      expect(draft.cardVisitId, isNull);
    });

    testWidgets('faixa "Pedido para Rui"', (tester) async {
      await tester.pumpWidget(
        _app(const DirectRequestCreateHeader(workerName: 'Rui Costa')),
      );
      expect(find.text('Pedido para Rui'), findsOneWidget);
      expect(find.text('R'), findsOneWidget);
    });

    testWidgets('jardineiro sem serviços: "Ver todos os serviços"',
        (tester) async {
      var all = 0;
      await tester.pumpWidget(_app(DirectRequestServicesEmpty(
        workerName: 'Rui',
        onShowAllServices: () => all++,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Rui ainda não indicou serviços'), findsOneWidget);
      await tester.tap(find.text('Ver todos os serviços'));
      expect(all, 1);
    });

    testWidgets('erro dos serviços com "Tentar novamente"', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        _app(DirectRequestServicesError(onRetry: () => retries++)),
      );
      await tester.tap(find.text('Tentar novamente'));
      expect(retries, 1);
    });

    testWidgets('passo 4: o interruptor muda o texto', (tester) async {
      bool? changed;
      Widget banner(bool on) => _app(DirectRequestReviewBanner(
            data: DirectRequestReviewBannerViewData(
              titleLabel: 'Vai primeiro para Rui',
              descriptionLabel: 'Tem 24 horas para responder.',
              workerInitial: 'R',
              releaseOptionTitleLabel: directReleaseOptionTitle,
              releaseOptionDescriptionLabel:
                  directReleaseOptionDescription('Rui', autoRelease: on),
              allowAutomaticReleaseToAll: on,
            ),
            onAutomaticReleaseChanged: (value) => changed = value,
          ));

      await tester.pumpWidget(banner(true));
      await tester.pumpAndSettle();
      expect(find.text(directReleaseOptionTitle), findsOneWidget);
      expect(find.textContaining('fica logo visível para todos'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      expect(changed, isFalse);

      await tester.pumpWidget(banner(false));
      await tester.pumpAndSettle();
      expect(find.textContaining('fica parado e decides tu'), findsOneWidget);
    });

    testWidgets('A5 sem interruptor continua igual', (tester) async {
      await tester.pumpWidget(_app(const DirectRequestReviewBanner(
        data: DirectRequestReviewBannerViewData(
          titleLabel: 'Vai primeiro para Rui',
          descriptionLabel: 'Tem 24 horas para responder.',
          workerInitial: 'R',
        ),
      )));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsNothing);
    });
  });

  group('detalhe do cliente', () {
    test('parado depois do prazo, com o interruptor desligado', () {
      final texts = directBannerTexts(
        _job(
          direct: DirectRequestStatus.onHold,
          holdReason: 'expired',
          autoRelease: false,
        ),
        workerName: 'Rui Costa',
      )!;
      expect(texts.kind, DirectBannerKind.onHold);
      expect(texts.title, 'Rui não respondeu a tempo');
      expect(texts.description,
          'O pedido está parado. Queres mostrá-lo a outros jardineiros?');
    });

    test('parado depois de recusar', () {
      final texts = directBannerTexts(
        _job(
          direct: DirectRequestStatus.onHold,
          holdReason: 'declined',
          autoRelease: false,
        ),
        workerName: 'Rui',
      )!;
      expect(texts.kind, DirectBannerKind.onHold);
      expect(texts.title, 'Rui não pode desta vez');
    });

    test('com o interruptor ligado continua a abrir a todos', () {
      final texts = directBannerTexts(
        _job(direct: DirectRequestStatus.expired),
        workerName: 'Rui',
      )!;
      expect(texts.kind, DirectBannerKind.released);
    });

    test('próximo passo do pedido parado', () {
      expect(
        clientJobNextStepLabel(_job(
          direct: DirectRequestStatus.onHold,
          holdReason: 'expired',
          autoRelease: false,
        )),
        'O pedido está parado. Decide se o mostras a outros jardineiros.',
      );
    });

    testWidgets('parado: "Mostrar a todos" e "Cancelar pedido"',
        (tester) async {
      var released = 0;
      var cancelled = 0;
      await tester.pumpWidget(_app(DirectRequestWaitingBanner(
        data: const DirectRequestWaitingBannerViewData(
          display: DirectRequestWaitingDisplay.onHold,
          titleLabel: 'Rui não respondeu a tempo',
          descriptionLabel:
              'O pedido está parado. Queres mostrá-lo a outros jardineiros?',
          workerInitial: 'R',
          releaseActionLabel: 'Mostrar a todos',
          cancelActionLabel: 'Cancelar pedido',
        ),
        onReleaseToAll: () async {
          released++;
          return 'Não foi possível mostrar o pedido a todos. Tenta novamente.';
        },
        onCancelRequest: () => cancelled++,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar pedido'));
      expect(cancelled, 1);
      await tester.tap(find.text('Mostrar a todos'));
      await tester.pumpAndSettle();
      expect(released, 1);
      expect(
        find.text('Não foi possível mostrar o pedido a todos. Tenta novamente.'),
        findsOneWidget,
      );
    });
  });

  group('lado do jardineiro', () {
    test('fora da área', () {
      expect(outsideAreaLabel(12.4), 'Fora da tua área, a 12 km');
    });

    testWidgets('pedido pelo cartão fora da área e depois do prazo',
        (tester) async {
      await tester.pumpWidget(_app(const WorkerDirectRequestCard(
        data: WorkerDirectRequestViewData(
          tagLabel: 'Pedido só para ti · prazo terminado',
          titleLabel: 'Marta pediu-te orçamento pelo teu cartão',
          explanationLabel: 'Se não responderes a tempo, Marta decide se '
              'mostra o pedido a outros jardineiros.',
          outsideAreaLabel: 'Fora da tua área, a 12 km',
          noticeLabel: 'Marta vai decidir se mostra o pedido a outros '
              'jardineiros. Ainda podes enviar proposta.',
          history: AsyncValue.data(null),
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Marta pediu-te orçamento pelo teu cartão'),
          findsOneWidget);
      expect(find.text('Fora da tua área, a 12 km'), findsOneWidget);
      expect(find.text('Podes enviar proposta na mesma. Conta com a deslocação.'),
          findsOneWidget);
      expect(find.textContaining('Marta vai decidir'), findsOneWidget);
    });

    test('origem do pedido', () {
      expect(DirectRequestOrigin.fromString('public_card'),
          DirectRequestOrigin.publicCard);
      expect(DirectRequestStatus.fromString('on_hold'),
          DirectRequestStatus.onHold);
      expect(_job(direct: DirectRequestStatus.onHold).isDirectOnHold, isTrue);
    });
  });
}
