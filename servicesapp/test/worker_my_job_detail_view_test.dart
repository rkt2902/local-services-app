import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/widgets/app_whatsapp_button.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';
import 'package:servicesapp/core/theme/app_status_presentation.dart';
import 'package:servicesapp/core/utils/date_labels.dart';
import 'package:servicesapp/features/ratings/application/rating_providers.dart';
import 'package:servicesapp/features/worker/application/worker_job_rules.dart';
import 'package:servicesapp/features/worker/presentation/widgets/worker_my_job_detail_view.dart';

WorkerMyJobDetailViewData _data({
  JobStatus jobStatus = JobStatus.confirmed,
  bool canStart = false,
  WorkerInactiveJobViewData? inactive,
  WorkerCompletedJobViewData? completed,
  WorkerJobTeamViewData? team,
  List<AcceptedHelper> helpers = const [],
  bool canRequestHelpers = true,
}) {
  return WorkerMyJobDetailViewData(
    jobId: 'job-1',
    proposalStatus: ProposalStatus.accepted,
    jobStatus: jobStatus,
    statusPresentation: const AppStatusPresentation(
        label: 'Agendado', color: AppStatusColor.success),
    serviceLabel: 'Corte de relva',
    titleSubtitle: 'Sofia Marques · Cascais',
    dateLabel: '23/10/2026',
    confirmedScheduleLabel: 'Qui, 23/10 · 9:00',
    addressLabel: 'Rua das Flores 12, Cascais',
    locationLat: 0,
    locationLng: 0,
    urgent: false,
    description: '',
    photoUrls: const [],
    hourlyRateLabel: '20,00 €/h',
    estimatedTotalLabel: '40 a 80 €',
    peopleNeeded: 1,
    timelineSteps: const [],
    clientId: 'client-1',
    clientName: 'Sofia Marques',
    clientAvatarUrl: null,
    clientPhone: '912345678',
    rescheduleStatus: null,
    rescheduleProposedByMe: false,
    proposedRescheduleLabel: '',
    cancelBlockedBy24h: false,
    helpersForRating: helpers,
    agreedPriceLabel: '60 € · 2 a 4h',
    canMarkCompleted: false,
    canStart: canStart,
    startHint: 'Disponível a partir das 8:00 de qui, 23/10',
    helpTeamLoaded: true,
    helpTeam: team,
    canRequestHelpers: canRequestHelpers,
    inactive: inactive,
    completed: completed,
  );
}

Widget _screen(
  WorkerMyJobDetailViewData data, {
  VoidCallback? onBrowse,
  Map<String, Rating?> ratings = const {},
}) {
  return ProviderScope(
    overrides: [
      myRatingForJobAndRateeProvider.overrideWith(
        (ref, args) async => ratings[args.$2],
      ),
    ],
    child: MaterialApp(
      home: WorkerMyJobDetailScreen(
        data: data,
        onBack: () {},
        onCallClientPressed: () {},
        onRequestHelpersPressed: () {},
        onViewTeamPressed: () {},
        onMarkCompleted: () async => false,
        onStartJob: () async {},
        onReportProblem: () {},
        onProposeReschedule: () {},
        onAcceptReschedule: () {},
        onRejectReschedule: () {},
        onCancelJob: () {},
        onWithdrawProposal: () {},
        onPhotoTap: (_) {},
        onWorkPhotoTap: (_, _) {},
        onBrowseAvailableJobs: onBrowse ?? () {},
      ),
    ),
  );
}

void main() {
  group('rótulos do design A1', () {
    test('data abreviada com dia da semana', () {
      final now = DateTime(2026, 10, 19);
      expect(shortWeekdayDateLabel(DateTime(2026, 10, 22), now: now),
          'Qui, 22/10');
      expect(shortWeekdayDateLabel(DateTime(2027, 1, 4), now: now),
          'Seg, 04/01/2027');
    });

    test('data e hora do trabalho', () {
      final now = DateTime(2026, 10, 19);
      final day = DateTime(2026, 10, 22);
      expect(
        workerScheduleLabel(
            date: day, time: '09:00:00', flexible: false, now: now),
        'Qui, 22/10 · 9:00',
      );
      expect(
        workerScheduleLabel(date: day, time: null, flexible: true, now: now),
        'Qui, 22/10 · horário flexível',
      );
      expect(
        workerScheduleLabel(date: null, time: null, flexible: false),
        'Data a combinar',
      );
    });

    test('quando abre o "Iniciar trabalho"', () {
      final now = DateTime(2026, 10, 19, 10);
      expect(
        startJobHint(
            canStart: false, opensAt: DateTime(2026, 10, 22, 8), now: now),
        'Disponível a partir das 8:00 de qui, 22/10',
      );
      expect(
        startJobHint(
            canStart: false, opensAt: DateTime(2026, 10, 19, 14, 30), now: now),
        'Disponível a partir das 14:30 de hoje',
      );
      expect(
        startJobHint(
            canStart: false, opensAt: DateTime(2026, 10, 22), now: now),
        'Disponível a partir de qui, 22/10',
      );
      expect(
        startJobHint(canStart: true, opensAt: null, now: now),
        'O cliente recebe um aviso quando começares.',
      );
    });
  });

  testWidgets('agendado: equipa, WhatsApp, remarcar e iniciar bloqueado',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_screen(_data(
      team: const WorkerJobTeamViewData(
        memberNames: ['Rui Costa'],
        emptySlots: 1,
        filledLabel: '1 de 2 vagas',
        pendingLabel: '2 candidatos por decidir',
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Qui, 23/10 · 9:00'), findsOneWidget);
    expect(find.byType(AppWhatsAppButton), findsOneWidget);
    expect(find.text('1 de 2 vagas'), findsOneWidget);
    expect(find.text('RC'), findsOneWidget);
    expect(find.text('2 candidatos por decidir'), findsOneWidget);
    expect(
      find.text(
          'Só podes remarcar ou cancelar até ao dia anterior ao trabalho.'),
      findsOneWidget,
    );
    expect(find.text('Remarcar'), findsOneWidget);
    expect(find.text('Iniciar trabalho'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.text('Disponível a partir das 8:00 de qui, 23/10'),
        findsOneWidget);
  });

  testWidgets('cancelado: sem WhatsApp nem ações, só "Ver pedidos disponíveis"',
      (tester) async {
    var browsed = false;
    await tester.pumpWidget(_screen(
      _data(
        jobStatus: JobStatus.cancelled,
        inactive: const WorkerInactiveJobViewData(
          title: 'O cliente cancelou este trabalho',
          body: 'Cancelado a 20/10. Não precisas de fazer nada.',
          expired: false,
          areaLabel: 'Oeiras',
        ),
      ),
      onBrowse: () => browsed = true,
    ));
    await tester.pumpAndSettle();

    expect(find.text('O cliente cancelou este trabalho'), findsOneWidget);
    expect(find.text('Oeiras'), findsOneWidget);
    expect(find.text('Rua das Flores 12, Cascais'), findsNothing);
    expect(find.byType(AppWhatsAppButton), findsNothing);
    expect(find.text('Remarcar'), findsNothing);
    expect(find.text('Iniciar trabalho'), findsNothing);
    expect(find.byIcon(Icons.event_busy_outlined), findsOneWidget);

    await tester.tap(find.text('Ver pedidos disponíveis'));
    expect(browsed, isTrue);
  });

  testWidgets('expirado usa a ampulheta', (tester) async {
    await tester.pumpWidget(_screen(_data(
      jobStatus: JobStatus.noResponse,
      inactive: const WorkerInactiveJobViewData(
        title: 'Este pedido expirou',
        body: 'Não precisas de fazer nada.',
        expired: true,
        areaLabel: 'Oeiras',
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.hourglass_disabled_rounded), findsOneWidget);
  });

  testWidgets(
      'concluído: avaliar cliente, ajudante avaliado e avaliação recebida',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_screen(
      _data(
        jobStatus: JobStatus.completed,
        helpers: const [
          AcceptedHelper(workerId: 'h1', fullName: 'Rui Costa'),
          AcceptedHelper(workerId: 'h2', fullName: 'Ana Lopes'),
        ],
        completed: const WorkerCompletedJobViewData(
          metaLabel: 'Concluído a 23/10. Tempo registado: 2h 40min.',
          receivedReview: WorkerReceivedReviewViewData(
            authorFirstName: 'Sofia',
            stars: 5,
            comment: 'Muito cuidadoso, recomendo.',
          ),
        ),
      ),
      ratings: {
        'h2': Rating(
          id: 'r1',
          jobId: 'job-1',
          raterId: 'me',
          rateeId: 'h2',
          stars: 4,
          createdAt: DateTime(2026, 10, 23),
        ),
      },
    ));
    await tester.pumpAndSettle();

    // Uma vez no cartão; a outra é o AppSuccessFeedback escondido.
    expect(find.text('Trabalho concluído'), findsWidgets);
    expect(find.text('Concluído a 23/10. Tempo registado: 2h 40min.'),
        findsOneWidget);
    expect(find.text('Avaliar o cliente'), findsOneWidget);
    expect(find.text('Avaliar: Rui Costa'), findsOneWidget);
    expect(find.text('Ana Lopes'), findsOneWidget);
    expect(find.text('Ajudante · avaliação enviada'), findsOneWidget);
    expect(find.text('Sofia avaliou-te com 5'), findsOneWidget);
    expect(find.text('"Muito cuidadoso, recomendo."'), findsOneWidget);
    // Sem fotos guardadas não aparecem os quadrados de antes e depois.
    expect(find.text('Antes'), findsNothing);
  });

  testWidgets('ajudantes: botão até à véspera, nada no dia sem equipa',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_screen(_data()));
    await tester.pumpAndSettle();
    expect(find.text('Preciso de ajudantes'), findsOneWidget);

    await tester.pumpWidget(_screen(_data(canRequestHelpers: false)));
    await tester.pumpAndSettle();
    expect(find.text('Preciso de ajudantes'), findsNothing);
  });

  testWidgets('equipa: ajudante com foto não mostra as iniciais',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_screen(_data(
      team: const WorkerJobTeamViewData(
        memberNames: ['Rui Costa', 'Ana Silva'],
        memberAvatarUrls: ['https://example.com/rui.jpg', null],
        emptySlots: 0,
        filledLabel: '2 de 2 vagas',
      ),
    )));
    await tester.pump();
    expect(find.text('RC'), findsNothing);
    expect(find.text('AS'), findsOneWidget);
  });
}
