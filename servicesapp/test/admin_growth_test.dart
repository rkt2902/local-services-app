import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/admin/application/admin_labels.dart';
import 'package:servicesapp/features/admin/application/admin_providers.dart';
import 'package:servicesapp/features/admin/data/admin_growth_models.dart';
import 'package:servicesapp/features/admin/data/admin_repository.dart';
import 'package:servicesapp/features/admin/presentation/admin_funnel_page.dart';
import 'package:servicesapp/features/admin/presentation/admin_notices_page.dart';
import 'package:servicesapp/features/admin/presentation/admin_shell.dart';
import 'package:servicesapp/features/notifications/data/notification_types.dart';
import 'package:servicesapp/features/worker/application/worker_providers.dart';
import 'package:servicesapp/features/worker/data/service_type_model.dart';

// Painel de admin, fase 3 (0081): funil, CSV e avisos a grupos. As RPCs
// (contagens, recusas, registo) são testadas na BD
// (supabase/tests/audit/80_admin_growth.sql).

Map<String, dynamic> _funnelJson({Object? median = 5.5}) => {
  'days': 30,
  'clients': {
    'signed_up': 20,
    'posted': 10,
    'got_proposal': 8,
    'hired': 5,
    'completed': 4,
    'rated': 2,
  },
  'jobs': {
    'created': 12,
    'with_proposal': 9,
    'accepted': 6,
    'completed': 4,
    'rated': 2,
    'open': 3,
    'no_response': 2,
    'cancelled': 1,
    'median_hours_to_first_proposal': median,
  },
  'workers': {
    'signed_up': 0,
    'profile_ready': 0,
    'proposed': 0,
    'hired': 0,
    'completed': 0,
    'paid_plan': 0,
  },
};

class _FakeRepo implements AdminRepository {
  int audienceCalls = 0;
  int count = 7;
  final sent = <({String title, AdminNoticeAudience audience, int expected})>[];

  @override
  Future<int> noticeAudience(AdminNoticeAudience audience) async {
    audienceCalls++;
    return count;
  }

  @override
  Future<int> sendNotice({
    required String title,
    required String body,
    required AdminNoticeAudience audience,
    required int expected,
  }) async {
    sent.add((title: title, audience: audience, expected: expected));
    return expected;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('funil', () {
    test('lê os três funis e a mediana', () {
      final f = AdminFunnel.fromJson(_funnelJson());
      expect(f.clients.map((s) => s.count), [20, 10, 8, 5, 4, 2]);
      expect(f.jobs.first.label, 'Pedidos criados');
      expect(f.jobs.length, 5);
      expect(f.workers.last.label, 'Plano Pro ou Pro+');
      expect(f.jobsOpen, 3);
      expect(f.jobsNoResponse, 2);
      expect(f.jobsCancelled, 1);
      expect(f.medianHoursToFirstProposal, 5.5);
    });

    test('JSON vazio dá zeros, sem rebentar', () {
      final f = AdminFunnel.fromJson(const {});
      expect(f.clients.every((s) => s.count == 0), isTrue);
      expect(f.medianHoursToFirstProposal, isNull);
    });

    test('percentagem do primeiro degrau', () {
      expect(adminFunnelPercent(5, 20), '25%');
      expect(adminFunnelPercent(1, 3), '33%');
      expect(adminFunnelPercent(0, 0), '—');
    });

    testWidgets('mostra os três cartões e o rodapé dos pedidos', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminFunnelView(
                funnel: AdminFunnel.fromJson(_funnelJson()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Clientes'), findsOneWidget);
      expect(find.text('Pedidos'), findsOneWidget);
      expect(find.text('Jardineiros'), findsOneWidget);
      expect(find.text('50%'), findsWidgets);
      expect(find.textContaining('3 abertos · 2 sem resposta'), findsOneWidget);
      expect(find.textContaining('(mediana)'), findsOneWidget);
      // Jardineiros sem registos: sem base, sem percentagem.
      expect(find.text('—'), findsNWidgets(6));
    });

    testWidgets('sem mediana, o rodapé não fala dela', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminFunnelView(
                funnel: AdminFunnel.fromJson(_funnelJson(median: null)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('mediana'), findsNothing);
    });

    test('períodos: 30 dias por omissão existe e "Tudo" é null', () {
      expect(adminFunnelPeriods.map((p) => p.$2), [7, 30, 90, null]);
    });
  });

  group('CSV', () {
    test('separador ;, BOM, CRLF, aspas e vírgula decimal', () {
      final csv = adminCsv(
        const AdminExportTable(
          columns: ['id', 'nome', 'media'],
          rows: [
            ['a', 'Ana; Lda', 4.5],
            ['b', 'Diz "olá"', null],
            ['c', 'linha\nnova', 3],
          ],
        ),
      );
      expect(csv.startsWith('﻿'), isTrue);
      final lines = csv.substring(1).split('\r\n');
      expect(lines[0], 'id;nome;media');
      expect(lines[1], 'a;"Ana; Lda";4,5');
      expect(lines[2], 'b;"Diz ""olá""";');
      expect(lines[3], 'c;"linha\nnova";3');
    });

    test('lê colunas e linhas do JSON', () {
      final t = AdminExportTable.fromJson({
        'columns': ['id', 'estado'],
        'rows': [
          ['x', 'open'],
        ],
      });
      expect(t.columns, ['id', 'estado']);
      expect(t.rows.single, ['x', 'open']);
      expect(AdminExportTable.fromJson(const {}).rows, isEmpty);
    });

    test('nome do ficheiro com a data', () {
      expect(
        adminCsvFileName(AdminExportKind.workers, DateTime(2026, 3, 4)),
        'projardim-jardineiros-2026-03-04.csv',
      );
    });

    testWidgets('um botão por lista, bloqueados durante uma exportação', (
      tester,
    ) async {
      AdminExportKind? asked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminExportCard(
              exporting: null,
              periodLabel: '30 dias',
              onExport: (k) => asked = k,
            ),
          ),
        ),
      );
      expect(find.textContaining('(30 dias)'), findsOneWidget);
      await tester.tap(find.text('Clientes'));
      expect(asked, AdminExportKind.clients);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminExportCard(
              exporting: AdminExportKind.jobs,
              periodLabel: '30 dias',
              onExport: (k) => asked = k,
            ),
          ),
        ),
      );
      asked = null;
      await tester.tap(find.text('Jardineiros'));
      expect(asked, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('destinatários', () {
    test('filtros de plano e serviço só valem para jardineiros', () {
      const workers = AdminNoticeAudience(
        tiers: {'pro_plus', 'pro'},
        serviceTypeId: 'st',
        area: '  Braga ',
      );
      expect(workers.toParams(), {
        'p_role': 'worker',
        'p_tiers': ['pro', 'pro_plus'],
        'p_service_type_id': 'st',
        'p_area': 'Braga',
      });
      final clients = workers.copyWith(role: 'client', area: '');
      expect(clients.toParams(), {
        'p_role': 'client',
        'p_tiers': null,
        'p_service_type_id': null,
        'p_area': null,
      });
    });

    test('igualdade ignora a ordem dos planos e espaços', () {
      const a = AdminNoticeAudience(tiers: {'free', 'pro'}, area: 'Braga');
      const b = AdminNoticeAudience(tiers: {'pro', 'free'}, area: 'Braga ');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.copyWith(serviceTypeId: () => 'x'), isFalse);
      expect(
        a
            .copyWith(serviceTypeId: () => 'x')
            .copyWith(serviceTypeId: () => null),
        a,
      );
    });

    test('rótulo do histórico', () {
      expect(
        adminNoticeAudienceLabel({
          'role': 'worker',
          'tiers': ['pro', 'pro_plus'],
          'area': 'Braga',
        }, serviceName: 'Relva'),
        'Jardineiros · Pro, Pro+ · Relva · Braga',
      );
      expect(adminNoticeAudienceLabel({'role': 'client'}), 'Clientes');
    });

    test('linha do histórico', () {
      final row = AdminNoticeRow.fromJson({
        'id': 'n1',
        'title': 'Manutenção',
        'body': 'A app vai estar parada.',
        'audience': {'role': 'client'},
        'recipients': 12,
        'read_count': 3,
        'created_at': '2026-11-16T10:00:00Z',
        'admin_email': 'a***@x.pt',
        'total_count': 1,
      });
      expect(row.recipients, 12);
      expect(row.readCount, 3);
      expect(row.createdAt, isNotNull);
      expect(row.audience['role'], 'client');
    });
  });

  group('página Avisos', () {
    Future<_FakeRepo> pumpPage(
      WidgetTester tester, {
      List<AdminNoticeRow> notices = const [],
    }) async {
      _tall(tester);
      final repo = _FakeRepo();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminRepositoryProvider.overrideWithValue(repo),
            adminNoticesProvider.overrideWith((ref) async => notices),
            serviceTypesProvider.overrideWith(
              (ref) async => const [
                ServiceType(id: 'st1', name: 'Corte de relva', slug: 'relva'),
              ],
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: AdminNoticesPage())),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('conta, confirma e envia com o número contado', (tester) async {
      final repo = await pumpPage(tester);
      expect(find.text('Conta os destinatários primeiro'), findsOneWidget);
      expect(find.text('Ainda sem avisos'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Título'),
        'Novidade',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Texto'),
        'Já podes mostrar o teu cartão em PDF.',
      );
      await tester.pump();
      expect(find.text('Pré-visualização'), findsOneWidget);

      await tester.tap(find.text('Contar destinatários'));
      await tester.pumpAndSettle();
      expect(find.text('7 pessoas'), findsOneWidget);

      await tester.tap(find.text('Enviar a 7 pessoas'));
      await tester.pumpAndSettle();
      expect(find.text('Enviar a 7 pessoas?'), findsOneWidget);
      await tester.tap(find.text('Enviar'));
      await tester.pumpAndSettle();

      expect(repo.sent.single.expected, 7);
      expect(repo.sent.single.title, 'Novidade');
      expect(repo.sent.single.audience.role, 'worker');
      // Formulário limpo, contagem esquecida.
      expect(find.text('Conta os destinatários primeiro'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('mudar filtros obriga a contar outra vez', (tester) async {
      final repo = await pumpPage(tester);
      await tester.tap(find.text('Contar destinatários'));
      await tester.pumpAndSettle();
      expect(find.text('7 pessoas'), findsOneWidget);

      await tester.tap(find.text('Pro'));
      await tester.pumpAndSettle();
      expect(find.text('7 pessoas'), findsNothing);

      // Clientes: sem filtros de plano nem serviço.
      await tester.tap(find.text('Clientes'));
      await tester.pumpAndSettle();
      expect(find.text('Pro+'), findsNothing);
      expect(find.text('Todos os serviços'), findsNothing);
      expect(repo.audienceCalls, 1);
    });

    testWidgets('ninguém com os filtros: não deixa enviar', (tester) async {
      final repo = await pumpPage(tester);
      repo.count = 0;
      await tester.tap(find.text('Contar destinatários'));
      await tester.pumpAndSettle();
      expect(find.text('Ninguém com estes filtros.'), findsOneWidget);
      expect(find.text('Conta os destinatários primeiro'), findsOneWidget);
    });

    testWidgets('histórico com público, leituras e serviço', (tester) async {
      await pumpPage(
        tester,
        notices: [
          AdminNoticeRow(
            id: 'n1',
            title: 'Manutenção',
            body: 'A app vai estar parada às 3h.',
            audience: const {
              'role': 'worker',
              'tiers': ['pro'],
              'service_type_id': 'st1',
            },
            recipients: 12,
            readCount: 3,
            createdAt: DateTime(2026, 11, 16, 10),
            adminEmail: 'a***@x.pt',
          ),
        ],
      );
      expect(find.text('Manutenção'), findsOneWidget);
      expect(find.text('Jardineiros · Pro · Corte de relva'), findsOneWidget);
      expect(find.textContaining('12 destinatários · 3 leram'), findsOneWidget);
    });
  });

  test('secções e tipo de notificação novos', () {
    expect(AdminSection.fromLocation('/admin/funil'), AdminSection.funnel);
    expect(AdminSection.fromLocation('/admin/avisos'), AdminSection.notices);
    expect(NotificationType.adminNotice, 'admin_notice');
    expect(adminHistoryActionLabel('send_notice'), 'Aviso enviado a um grupo');
    expect(adminHistoryActionLabel('export_csv'), 'Lista exportada em CSV');
  });
}
