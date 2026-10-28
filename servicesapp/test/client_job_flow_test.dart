import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/models/job_flow_stage.dart';
import 'package:servicesapp/core/widgets/app_tab_header.dart';
import 'package:servicesapp/core/widgets/job_flow_stepper.dart';
import 'package:servicesapp/features/help_requests/data/help_request_model.dart';
import 'package:servicesapp/features/jobs/application/client_job_flow.dart';
import 'package:servicesapp/features/jobs/data/job_model.dart';

JobRequest _job({
  JobStatus status = JobStatus.confirmed,
  int proposals = 0,
  DateTime? startedAt,
}) => JobRequest(
  id: 'j',
  clientId: 'c',
  serviceTypeId: 's',
  addressText: '',
  locationLat: 0,
  locationLng: 0,
  description: '',
  status: status,
  proposalCount: proposals,
  confirmedDate: DateTime(2026, 10, 31),
  confirmedTime: '08:30:00',
  startedAt: startedAt,
  expiresAt: DateTime(2026, 12, 1),
  createdAt: DateTime(2026, 10, 1),
);

HelpRequest _hr(HelpRequestStatus status, int slots) => HelpRequest(
  id: 'hr-$status',
  jobId: 'j',
  proposalId: 'p',
  slotsNeeded: slots,
  status: status,
  equipmentRequired: false,
  createdPostConfirmation: false,
  createdAt: DateTime(2026, 10, 21),
);

void main() {
  group('equipa vista pela cliente', () {
    test(
      'sem pedido de ajudantes: vagas da proposta, sem contar o responsável',
      () {
        final team = clientJobTeam(
          proposalPeopleNeeded: 3,
          helpRequests: const [],
          helperNames: const [],
        );
        expect(team.helpersNeeded, 2);
        expect(team.countLabel, '0/2');
        expect(team.isComplete, isFalse);
      },
    );

    test('proposta só com o responsável: sem equipa', () {
      final team = clientJobTeam(
        proposalPeopleNeeded: 1,
        helpRequests: const [],
        helperNames: const [],
      );
      expect(team.hasHelpers, isFalse);
      expect(team.countLabel, isNull);
      expect(team.isComplete, isTrue);
    });

    test('pedido por aprovar conta para as vagas e para a aprovação', () {
      final team = clientJobTeam(
        proposalPeopleNeeded: 1,
        helpRequests: [_hr(HelpRequestStatus.pendingApproval, 2)],
        helperNames: const [],
      );
      expect(team.helpersNeeded, 2);
      expect(team.pendingApprovalSlots, 2);
    });

    test('pedidos fechados: fica quem já está', () {
      final team = clientJobTeam(
        proposalPeopleNeeded: 3,
        helpRequests: [_hr(HelpRequestStatus.filled, 2)],
        helperNames: const ['Pedro Nunes'],
      );
      expect(team.helpersNeeded, 1);
      expect(team.countLabel, '1/1');
      expect(team.isComplete, isTrue);
    });

    test('pedido cancelado sem ninguém: sem equipa', () {
      final team = clientJobTeam(
        proposalPeopleNeeded: 3,
        helpRequests: [_hr(HelpRequestStatus.cancelled, 2)],
        helperNames: const [],
      );
      expect(team.hasHelpers, isFalse);
    });
  });

  group('fase do stepper', () {
    const none = ClientJobTeam(helpersNeeded: 0, helperNames: []);
    const forming = ClientJobTeam(helpersNeeded: 2, helperNames: ['Pedro']);

    test('pedido aberto: Pedido sem propostas, Proposta com', () {
      expect(
        clientJobFlowStage(_job(status: JobStatus.open), none),
        JobFlowStage.request,
      );
      expect(
        clientJobFlowStage(_job(status: JobStatus.open, proposals: 2), none),
        JobFlowStage.proposal,
      );
    });

    test('marcado: Equipa enquanto falta gente, No dia sem ajudantes', () {
      expect(clientJobFlowStage(_job(), forming), JobFlowStage.team);
      expect(clientJobFlowStage(_job(), none), JobFlowStage.onTheDay);
    });

    test('em curso é No dia mesmo com a equipa incompleta', () {
      expect(
        clientJobFlowStage(_job(startedAt: DateTime(2026, 10, 31, 8)), forming),
        JobFlowStage.onTheDay,
      );
    });

    test('dado como feito e concluído: Feito', () {
      expect(
        clientJobFlowStage(_job(status: JobStatus.awaitingConfirmation), none),
        JobFlowStage.completed,
      );
      expect(
        clientJobFlowStage(_job(status: JobStatus.completed), none),
        JobFlowStage.completed,
      );
    });
  });

  group('aviso muda com e sem ajudantes', () {
    test('sem ajudantes e por começar: sem aviso', () {
      expect(
        clientJobFlowBanner(
          job: _job(),
          team: const ClientJobTeam(helpersNeeded: 0, helperNames: []),
          workerName: 'João Silva',
        ),
        isNull,
      );
    });

    test('em curso sem ajudantes não fala de equipa', () {
      final banner = clientJobFlowBanner(
        job: _job(startedAt: DateTime(2026, 10, 31, 8, 34)),
        team: const ClientJobTeam(helpersNeeded: 0, helperNames: []),
        workerName: 'João Silva',
      )!;
      expect(banner.kind, ClientJobFlowBannerKind.started);
      expect(banner.title, startsWith('João começou às'));
      expect(banner.body, isNull);
    });

    test('em curso com ajudantes diz quem está', () {
      final banner = clientJobFlowBanner(
        job: _job(startedAt: DateTime(2026, 10, 31, 8, 34)),
        team: const ClientJobTeam(
          helpersNeeded: 2,
          helperNames: ['Pedro Nunes', 'Tiago Sousa'],
        ),
        workerName: 'João Silva',
      )!;
      expect(banner.body, 'Está com Pedro e Tiago.');
    });

    test('a formar, por aprovar e completa', () {
      expect(
        clientJobFlowBanner(
          job: _job(),
          team: const ClientJobTeam(helpersNeeded: 2, helperNames: []),
          workerName: 'João Silva',
        )!.title,
        'João está a juntar a equipa.',
      );
      final approve = clientJobFlowBanner(
        job: _job(),
        team: const ClientJobTeam(
          helpersNeeded: 1,
          helperNames: [],
          pendingApprovalSlots: 1,
        ),
        workerName: 'João Silva',
      )!;
      expect(approve.kind, ClientJobFlowBannerKind.approveTeam);
      expect(approve.title, 'João quer levar 1 ajudante.');
      expect(
        clientJobFlowBanner(
          job: _job(),
          team: const ClientJobTeam(
            helpersNeeded: 2,
            helperNames: ['Pedro Nunes', 'Tiago Sousa'],
          ),
          workerName: 'João Silva',
        )!.body,
        'João vem com Pedro e Tiago.',
      );
    });
  });

  test('subtítulo: nome, dia e hora', () {
    expect(
      clientJobFlowSubtitle(
        job: _job(),
        workerName: 'João Silva',
        now: DateTime(2026, 10, 27),
      ),
      'João Silva · Sáb, 31/10 · 08:30',
    );
  });

  testWidgets('stepper marca a fase atual e o separador mostra 1/2', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const JobFlowStepper(stage: JobFlowStage.team),
              AppTabs(
                items: const [
                  AppTabItem(label: 'Resumo'),
                  AppTabItem(label: 'Equipa', badge: '1/2'),
                ],
                selectedIndex: 0,
                onSelected: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    for (final s in JobFlowStage.values) {
      expect(find.text(s.label, skipOffstage: false), findsWidgets);
    }
    expect(find.text('1/2'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(JobFlowStepper)).label,
      contains('Equipa, 3 de 5'),
    );
  });

  testWidgets('sem ajudantes o stepper não tem a fase Equipa', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: JobFlowStepper(stage: JobFlowStage.team, showTeam: false),
        ),
      ),
    );
    expect(find.text('Equipa'), findsNothing);
    expect(find.text('No dia'), findsOneWidget);
    // Quem estaria em Equipa já está à espera do dia.
    expect(
      tester.getSemantics(find.byType(JobFlowStepper)).label,
      contains('No dia, 3 de 4'),
    );
  });
}
