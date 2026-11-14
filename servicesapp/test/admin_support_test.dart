import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:servicesapp/features/admin/application/admin_providers.dart';
import 'package:servicesapp/features/admin/presentation/admin_jobs_page.dart';
import 'package:servicesapp/features/worker/application/worker_providers.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/admin/application/admin_labels.dart';
import 'package:servicesapp/features/admin/data/admin_support_models.dart';
import 'package:servicesapp/features/admin/presentation/admin_clients_page.dart';
import 'package:servicesapp/features/admin/presentation/admin_shell.dart';
import 'package:servicesapp/features/admin/presentation/widgets/admin_job_detail_panel.dart';
import 'package:servicesapp/features/admin/presentation/widgets/admin_panel_widgets.dart';

// Painel de admin para suporte, fase A (0078): modelos, textos e vistas
// puras. As RPCs e o registo das consultas são testados na BD
// (supabase/tests/audit/50_admin_support.sql).

const _jobId = '4f8f1350-f963-42bc-84e5-ff2172cd9934';

Map<String, dynamic> _jobJson({List<Map<String, dynamic>>? timeline}) => {
      'job_id': _jobId,
      'status': 'awaiting_confirmation',
      'proposal_count': 2,
      'service_name': 'Corte de relva',
      'description': 'Relva alta nas traseiras',
      'urgency': 'urgent',
      'location_area': 'Benfica',
      'has_address': true,
      'date_mode': 'fixed',
      'confirmed_date': '2026-11-20',
      'confirmed_time': '09:00:00',
      'created_at': '2026-11-10T10:00:00Z',
      'auto_confirm_at': '2026-11-27T10:00:00Z',
      'is_direct': false,
      'photo_count': 3,
      'views': 2,
      'client': {'id': 'c1', 'full_name': 'Ana Silva', 'deleted': false},
      'worker': {'id': 'w1', 'full_name': 'Rui Costa', 'deleted': false},
      'timeline': timeline ??
          [
            {
              'at': '2026-11-10T10:00:00Z',
              'type': 'created',
              'actor_kind': 'client',
              'actor_name': 'Ana Silva',
              'data': {'date_mode': 'fixed'},
            },
            {
              'at': '2026-11-11T09:00:00Z',
              'type': 'proposal_sent',
              'actor_kind': 'worker',
              'actor_name': 'Rui Costa',
              'data': {},
            },
            {
              'at': '2026-11-12T09:00:00Z',
              'type': 'cancelled',
              'actor_kind': 'system',
              'data': {'reason_detail': 'teste'},
            },
          ],
      'proposals': [
        {
          'id': 'p1',
          'worker_id': 'w1',
          'worker_name': 'Rui Costa',
          'status': 'accepted',
          'is_accepted': true,
          'pricing_mode': 'fixed_total',
          'total_price': 120,
          'hours_min': 2,
          'hours_max': 4,
          'people_needed': 1,
          'includes': ['Recolha de resíduos'],
          'created_at': '2026-11-11T09:00:00Z',
        },
        {
          'id': 'p2',
          'worker_id': 'w2',
          'worker_name': 'Zé Santos',
          'status': 'superseded',
          'pricing_mode': 'hourly',
          'hourly_rate': 15,
          'days_min': 2,
          'days_max': 3,
          'people_needed': 1,
        },
      ],
      'team': [],
      'notifications': [
        {
          'user_name': 'Ana Silva',
          'user_role': 'client',
          'type': 'job_done',
          'title': 'Trabalho concluído',
          'read': false,
          'created_at': '2026-11-13T10:00:00Z',
          'had_push_token': false,
        },
      ],
      'reports': [
        {
          'reporter_name': 'Ana Silva',
          'description': 'Ficou por cortar metade',
          'created_at': '2026-11-13T11:00:00Z',
        },
      ],
      'ratings': [],
    };

Widget _app(Widget child) {
  return ProviderScope(
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

/// Ecrã de computador alto, para as listas construírem tudo.
void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('modelos', () {
    test('ficha do pedido lê cabeçalho, linha do tempo e listas', () {
      final job = AdminJobDetail.fromJson(_jobJson());
      expect(job.status, JobStatus.awaitingConfirmation);
      expect(job.urgent, isTrue);
      expect(job.client?.fullName, 'Ana Silva');
      expect(job.timeline, hasLength(3));
      expect(job.timeline.first.actorKind, AdminActorKind.client);
      expect(job.proposals.first.isFixedTotal, isTrue);
      expect(job.notifications.single.hadPushToken, isFalse);
      expect(job.autoConfirmAt, isNotNull);
    });

    test('estado desconhecido não rebenta e guarda o valor cru', () {
      final json = _jobJson()..['status'] = 'paused';
      final job = AdminJobDetail.fromJson(json);
      expect(job.status, isNull);
      expect(job.statusValue, 'paused');
    });

    test('resultado da pesquisa leva à ficha certa', () {
      final hit = AdminSearchHit.fromJson({
        'kind': 'client',
        'target_id': 'c1',
        'title': 'Ana',
        'subtitle': 'Cliente',
      });
      expect(hit?.route, '/admin/clientes/c1');
      expect(
          AdminSearchHit.fromJson({'kind': 'job', 'target_id': 'j'})?.route,
          '/admin/pedidos/j');
      expect(AdminSearchHit.fromJson({'kind': 'x', 'target_id': 'j'}), isNull);
    });

    test('mudar um filtro volta à primeira página', () {
      const f = AdminJobsFilter(page: 3);
      final g = f.copyWith(withReport: true);
      expect(g.page, 0);
      expect(g.withReport, isTrue);
      expect(f.copyWith(page: 4).page, 4);
      expect(const AdminJobsFilter(), const AdminJobsFilter());
      expect(
          const AdminClientsFilter(page: 2).copyWith(search: 'ana').page, 0);
    });

    test('evento reconstruído dos carimbos é reconhecido', () {
      final e = AdminJobEvent.fromJson({
        'type': 'created',
        'actor_kind': 'client',
        'data': {'backfill': true},
      });
      expect(e.isBackfill, isTrue);
    });
  });

  group('textos', () {
    test('id curto e contagem decrescente', () {
      expect(adminShortId(_jobId), '#4f8f1350');
      final now = DateTime(2026, 11, 13, 12);
      expect(adminCountdownLabel(now.add(const Duration(hours: 5)), now: now),
          'faltam 5 h');
      expect(adminCountdownLabel(now.add(const Duration(days: 4)), now: now),
          'faltam 4 dias');
      expect(
          adminCountdownLabel(now.subtract(const Duration(minutes: 30)),
              now: now),
          'passou há 30 min');
      expect(adminCountdownLabel(null), isNull);
    });

    test('eventos da linha do tempo em português', () {
      expect(adminJobEventLabel('created', {}), 'Pedido criado');
      expect(adminJobEventLabel('created', {'reopened_from': 'x'}),
          'Pedido reaberto');
      expect(adminJobEventLabel('day_started', {'day': 2}), 'Dia 2 começado');
      expect(adminJobEventLabel('search_widened', {'extra_km': 10}),
          'Mostrado mais longe (+10 km)');
      expect(adminJobEventLabel('admin_reveal_address', {}),
          'Admin viu a morada');
      expect(adminJobEventLabel('algo_novo', {}), 'algo_novo');
      expect(adminActorLabel(AdminActorKind.system, 'x'), 'Sistema');
      expect(adminActorLabel(AdminActorKind.worker, 'Rui'), 'Jardineiro · Rui');
    });

    test('preço e duração da proposta', () {
      final job = AdminJobDetail.fromJson(_jobJson());
      expect(adminProposalPrice(job.proposals[0]), contains('valor total'));
      expect(adminProposalPrice(job.proposals[1]), endsWith('/h'));
      expect(adminProposalDuration(job.proposals[0]), '2 a 4 h');
      expect(adminProposalDuration(job.proposals[1]), '2 a 3 dias');
    });

    test('secção da barra lateral pelo endereço', () {
      expect(AdminSection.fromLocation('/admin'), AdminSection.overview);
      expect(AdminSection.fromLocation('/admin/pedidos/abc'), AdminSection.jobs);
      expect(AdminSection.fromLocation('/admin/clientes'), AdminSection.clients);
      expect(
          AdminSection.fromLocation('/admin/workers/x'), AdminSection.workers);
    });
  });

  group('vistas', () {
    testWidgets('ficha do pedido mostra cabeçalho, reporte e linha do tempo',
        (tester) async {
      _desktop(tester);
      final job = AdminJobDetail.fromJson(_jobJson());
      await tester.pumpWidget(_app(AdminJobDetailView(
        job: job,
        onOpenPerson: (_) {},
        onRefresh: () async {},
      )));
      await tester.pumpAndSettle();
      expect(find.text('Corte de relva'), findsOneWidget);
      expect(find.text('#4f8f1350'), findsOneWidget);
      expect(find.text('Urgente'), findsOneWidget);
      expect(find.textContaining('Ficou por cortar metade'), findsOneWidget);
      expect(find.text('Pedido criado'), findsOneWidget);
      expect(find.text('Proposta enviada'), findsOneWidget);
      expect(find.text('Motivo: teste'), findsOneWidget);
      // A morada exata não aparece no cabeçalho.
      expect(find.textContaining('Rua'), findsNothing);
    });

    testWidgets('separadores Propostas e Avisos', (tester) async {
      _desktop(tester);
      final job = AdminJobDetail.fromJson(_jobJson());
      String? opened;
      await tester.pumpWidget(_app(AdminJobDetailView(
        job: job,
        onOpenPerson: (r) => opened = r,
        onRefresh: () async {},
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Propostas (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Zé Santos'), findsOneWidget);
      expect(find.text('Fechada ou retirada'), findsOneWidget);
      await tester.tap(find.text('Abrir ficha do jardineiro').first);
      expect(opened, '/admin/workers/w1');

      await tester.tap(find.text('Avisos (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Trabalho concluído'), findsOneWidget);
      expect(find.text('Sem aparelho'), findsOneWidget);
      expect(find.text('Por ler'), findsOneWidget);
    });

    testWidgets('separador Fotos usa o widget dado (não chama a BD)',
        (tester) async {
      _desktop(tester);
      final job = AdminJobDetail.fromJson(_jobJson());
      await tester.pumpWidget(_app(AdminJobDetailView(
        job: job,
        initialTab: AdminJobTab.photos,
        photosTab: const Text('fotos de teste'),
        onOpenPerson: (_) {},
        onRefresh: () async {},
      )));
      await tester.pumpAndSettle();
      expect(find.text('fotos de teste'), findsOneWidget);
    });

    testWidgets('morada fica escondida até ao clique', (tester) async {
      _desktop(tester);
      var revealed = 0;
      await tester.pumpWidget(_app(AdminAddressView(
        zone: 'Benfica',
        hasAddress: true,
        address: null,
        loading: false,
        onReveal: () => revealed++,
      )));
      expect(find.text('Benfica'), findsOneWidget);
      await tester.tap(find.text('Mostrar morada'));
      expect(revealed, 1);

      await tester.pumpWidget(_app(const AdminAddressView(
        zone: 'Benfica',
        hasAddress: true,
        address: AdminRevealedAddress(
          addressText: 'Rua Exata 1',
          lat: null,
          lng: null,
          workerBaseLat: null,
          workerBaseLng: null,
          workerLocationName: 'Amadora',
          distanceKm: 4.2,
        ),
        loading: false,
        onReveal: _noop,
      )));
      await tester.pumpAndSettle();
      expect(find.text('Rua Exata 1'), findsOneWidget);
      expect(find.text('4.2 km'), findsOneWidget);
    });

    testWidgets('ficha do cliente', (tester) async {
      _desktop(tester);
      final client = AdminClientDetail.fromJson({
        'client_id': 'c1',
        'full_name': 'Ana Silva',
        'email': 'ana@exemplo.pt',
        'email_confirmed': false,
        'phone_masked': '••• ••• 001',
        'has_phone': true,
        'push_devices': 0,
        'jobs': [
          {
            'job_id': _jobId,
            'service_name': 'Poda',
            'status': 'completed',
            'has_report': true,
          },
        ],
        'ratings_given': [
          {'ratee_name': 'Rui', 'stars': 5, 'comment': 'Ótimo'},
        ],
        'ratings_received': [],
        'reports': [],
        'admin_history': [
          {'action': 'reveal_phone', 'created_at': '2026-11-13T10:00:00Z'},
        ],
      });
      String? openedJob;
      await tester.pumpWidget(_app(AdminClientDetailView(
        client: client,
        onOpenJob: (id) => openedJob = id,
        phone: const Text('telefone escondido'),
      )));
      await tester.pumpAndSettle();
      expect(find.text('ana@exemplo.pt (por confirmar)'), findsOneWidget);
      expect(find.text('telefone escondido'), findsOneWidget);
      expect(find.text('Nenhum'), findsOneWidget);
      expect(find.text('Telefone revelado', findRichText: true), findsNothing);
      expect(find.textContaining('Telefone revelado'), findsOneWidget);
      await tester.tap(find.text('Poda'));
      expect(openedJob, _jobId);
    });

    testWidgets('lado a lado em ecrã largo, ficha por cima em ecrã estreito',
        (tester) async {
      _desktop(tester);
      Widget split(double width, {bool selected = true}) => Center(
            child: SizedBox(
              width: width,
              height: 600,
              child: AdminSplitView(
                list: const Text('lista'),
                detailKey: selected ? 'x' : null,
                detailBuilder: selected
                    ? (overlay) => Text(overlay ? 'ficha por cima' : 'ficha')
                    : null,
                emptyDetail: const Text('vazio'),
              ),
            ),
          );
      await tester.pumpWidget(_app(split(1200)));
      await tester.pumpAndSettle();
      expect(find.text('lista'), findsOneWidget);
      expect(find.text('ficha'), findsOneWidget);

      await tester.pumpWidget(_app(split(1200, selected: false)));
      await tester.pumpAndSettle();
      expect(find.text('vazio'), findsOneWidget);

      await tester.pumpWidget(_app(split(600)));
      await tester.pumpAndSettle();
      expect(find.text('lista'), findsNothing);
      expect(find.text('ficha por cima'), findsOneWidget);
    });
    for (final width in [1400.0, 700.0]) {
      testWidgets('painel com lista e ficha abre sem erros de layout ($width px)',
          (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final row = AdminJobRow.fromJson({
          'job_id': _jobId,
          'service_name': 'Corte de relva',
          'client_name': 'Ana Silva',
          'worker_name': 'Rui Costa',
          'location_area': 'Benfica',
          'status': 'open',
          'proposal_count': 2,
          'created_at': '2026-11-10T10:00:00Z',
          'has_report': true,
          'is_direct': true,
          'has_helpers': true,
          'total_count': 1,
        });
        final router = GoRouter(
          initialLocation: '/admin/pedidos/$_jobId',
          routes: [
            GoRoute(
              path: '/admin/pedidos/:id',
              builder: (_, state) => AdminShell(
                location: state.matchedLocation,
                child: AdminJobsPage(selectedJobId: state.pathParameters['id']),
              ),
            ),
            GoRoute(
              path: '/admin/pedidos',
              builder: (_, state) => AdminShell(
                location: state.matchedLocation,
                child: const AdminJobsPage(),
              ),
            ),
          ],
        );
        await tester.pumpWidget(ProviderScope(
          overrides: [
            adminJobsProvider.overrideWith((ref, _) async => [row]),
            adminJobDetailProvider
                .overrideWith((ref, _) async => AdminJobDetail.fromJson(_jobJson())),
            serviceTypesProvider.overrideWith((ref) async => []),
          ],
          child: MaterialApp.router(routerConfig: router),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('#4f8f1350'), findsWidgets);
        if (width < adminSplitMinWidth) {
          // Ecrã estreito: a ficha por cima, com botão para voltar.
          await tester.tap(find.byTooltip('Voltar à lista'));
          await tester.pumpAndSettle();
          expect(find.text('Ana Silva → Rui Costa'), findsOneWidget);
        } else {
          expect(find.text('Ana Silva → Rui Costa'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}

void _noop() {}
