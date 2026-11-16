import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';
import 'package:servicesapp/features/admin/application/admin_labels.dart';
import 'package:servicesapp/features/admin/application/admin_providers.dart';
import 'package:servicesapp/features/admin/data/admin_resolve_models.dart';
import 'package:servicesapp/features/admin/data/admin_support_models.dart';
import 'package:servicesapp/features/admin/presentation/admin_cases_page.dart';
import 'package:servicesapp/features/admin/presentation/admin_log_page.dart';
import 'package:servicesapp/features/admin/presentation/admin_ratings_page.dart';
import 'package:servicesapp/features/admin/presentation/admin_reports_page.dart';
import 'package:servicesapp/features/admin/presentation/admin_shell.dart';
import 'package:servicesapp/features/admin/presentation/widgets/admin_action_dialogs.dart';
import 'package:servicesapp/features/admin/presentation/widgets/admin_job_actions.dart';
import 'package:servicesapp/features/client/application/job_request_form.dart';
import 'package:servicesapp/features/jobs/data/cancel_reasons.dart';
import 'package:servicesapp/features/jobs/data/job_model.dart';
import 'package:servicesapp/features/notifications/application/notification_presentation.dart';
import 'package:servicesapp/features/notifications/data/notification_types.dart';
import 'package:servicesapp/features/worker/application/worker_job_rules.dart';

// Painel de admin para suporte, fase B (0079): modelos, prazos, diálogos
// de ação e vistas. As RPCs (recusas, avisos, registo) são testadas na BD
// (supabase/tests/audit/60_admin_resolve.sql).

const _caseId = '7a1b2c3d-0000-4000-8000-000000000001';

Map<String, dynamic> _caseJson({
  String status = 'open',
  String? firstReplyAt,
  String? decision,
}) => {
  'case_id': _caseId,
  'number': 12,
  'kind': 'report',
  'status': status,
  'summary': 'Jardineiro não apareceu',
  'person_id': 'c1',
  'person_name': 'Ana Silva',
  'person_role': 'client',
  'person_email': 'ana@exemplo.pt',
  'job_id': '4f8f1350-f963-42bc-84e5-ff2172cd9934',
  'job_service': 'Corte de relva',
  'ack_due_at': '2026-11-17T10:00:00Z',
  'due_at': '2026-11-18T10:00:00Z',
  'first_reply_at': firstReplyAt,
  'created_at': '2026-11-16T10:00:00Z',
  'decision': decision,
  'total_count': 1,
  'reports': [
    {
      'id': 'r1',
      'description': 'Não apareceu',
      'status': 'in_review',
      'created_at': '2026-11-16T09:00:00Z',
    },
  ],
  'notes': [
    {
      'id': 'n1',
      'kind': 'reply',
      'body': 'Recebemos o teu reporte.',
      'created_at': '2026-11-16T11:00:00Z',
      'author_email': 'admin@projardim.pt',
    },
  ],
};

Widget _app(Widget child, {List<dynamic> overrides = const []}) {
  return ProviderScope(
    overrides: [...overrides],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

JobRequest _job({String? cancelReason, String? cancelledBy}) => JobRequest(
  id: 'j1',
  clientId: 'c1',
  serviceTypeId: 's1',
  addressText: 'Rua A 1, Braga',
  locationLat: 41.55,
  locationLng: -8.42,
  dateMode: DateMode.flexible,
  description: 'Cortar a relva',
  status: JobStatus.cancelled,
  cancelReason: cancelReason,
  cancelledBy: cancelledBy,
  expiresAt: DateTime(2026, 10, 10),
  createdAt: DateTime(2026, 10, 8),
);

void main() {
  group('prazos', () {
    final now = DateTime.utc(2026, 11, 16, 12);

    test('verde com folga, âmbar a menos de 24 h, vermelho passado', () {
      expect(
        adminDeadlineTone(now.add(const Duration(days: 2)), now: now),
        AdminDeadlineTone.green,
      );
      expect(
        adminDeadlineTone(now.add(const Duration(hours: 5)), now: now),
        AdminDeadlineTone.amber,
      );
      expect(
        adminDeadlineTone(now.subtract(const Duration(hours: 1)), now: now),
        AdminDeadlineTone.red,
      );
      expect(
        adminDeadlineTone(now, closed: true, now: now),
        AdminDeadlineTone.done,
      );
      expect(
        adminDeadlineStatusColor(AdminDeadlineTone.red),
        AppStatusColor.cancelled,
      );
    });

    test('texto do prazo', () {
      expect(
        adminDeadlineLabel(now.add(const Duration(hours: 5)), now: now),
        'Prazo: faltam 5 h',
      );
      expect(
        adminDeadlineLabel(now.subtract(const Duration(days: 3)), now: now),
        'Atrasado há 3 dias',
      );
      expect(adminDeadlineLabel(now, closed: true, now: now), 'Fechado');
    });

    test('sem resposta conta a receção; depois, o prazo do tipo', () {
      final waiting = AdminCaseRow.fromJson(_caseJson());
      expect(waiting.nextDueAt, DateTime.utc(2026, 11, 17, 10));
      final answered = AdminCaseRow.fromJson(
        _caseJson(firstReplyAt: '2026-11-16T11:00:00Z'),
      );
      expect(answered.nextDueAt, DateTime.utc(2026, 11, 18, 10));
    });
  });

  group('modelos', () {
    test('caso com notas, reportes e email de resposta', () {
      final d = AdminCaseDetail.fromJson(_caseJson());
      expect(d.row.number, 12);
      expect(d.row.kind, AdminCaseKind.report);
      expect(d.row.status, AdminCaseStatus.open);
      expect(d.replyEmail, 'ana@exemplo.pt');
      expect(d.notes.single.isReply, isTrue);
      expect(d.reports.single.status, 'in_review');
    });

    test('tipo desconhecido não rebenta', () {
      final row = AdminCaseRow.fromJson({..._caseJson(), 'kind': 'outro'});
      expect(row.kind, isNull);
      expect(row.kindValue, 'outro');
    });

    test('reporte, avaliação e linha do registo', () {
      final report = AdminReportRow.fromJson({
        'report_id': 'r1',
        'job_id': 'j1',
        'reporter_id': 'c1',
        'reporter_role': 'client',
        'description': 'x',
        'status': 'dismissed',
        'case_number': 3,
        'total_count': 1,
      });
      expect(report.reporterIsClient, isTrue);
      expect(report.closed, isTrue);
      expect(report.caseNumber, 3);

      final rating = AdminModerationRating.fromJson({
        'rating_id': 'x',
        'stars': 1,
        'hidden': true,
        'hidden_reason': 'personal_data',
        'total_count': 1,
      });
      expect(rating.hidden, isTrue);
      expect(
        AdminActionReason.labelOf(rating.hiddenReason),
        'Dados pessoais expostos',
      );

      final action = AdminActionRow.fromJson({
        'action_id': 'a1',
        'action': 'cancel_job',
        'details': {'reason': 'terms_violation', 'note': 'Faltou duas vezes.'},
        'total_count': 1,
      });
      expect(action.reason, 'terms_violation');
      expect(action.note, 'Faltou duas vezes.');
      expect(adminHistoryActionLabel(action.action), contains('suporte'));
      expect(adminIsReadAction('view_case'), isTrue);
      expect(adminIsReadAction('cancel_job'), isFalse);
    });

    test('mudar um filtro da caixa volta à primeira página', () {
      const f = AdminCasesFilter(page: 3);
      expect(f.copyWith(status: 'all').page, 0);
      expect(f.copyWith(kind: AdminCaseKind.abuse).kind, AdminCaseKind.abuse);
      expect(
        f.copyWith(kind: AdminCaseKind.abuse).copyWith(kind: null).kind,
        isNull,
      );
    });

    test('motivos iguais aos da BD', () {
      expect(AdminActionReason.values.map((r) => r.value), [
        'user_request',
        'app_error',
        'terms_violation',
        'illegal_content',
        'personal_data',
        'duplicate',
        'other',
      ]);
    });
  });

  group('ações e regras', () {
    test('ações do pedido pelo estado', () {
      expect(adminJobActionsFor(JobStatus.open), [AdminJobAction.cancel]);
      expect(adminJobActionsFor(JobStatus.confirmed), [
        AdminJobAction.complete,
        AdminJobAction.cancel,
      ]);
      expect(adminJobActionsFor(JobStatus.completed), [
        AdminJobAction.undoConfirmation,
      ]);
      expect(adminJobActionsFor(JobStatus.noResponse), [AdminJobAction.reopen]);
      expect(adminJobActionsFor(JobStatus.cancelled), isEmpty);
    });

    test('secções novas da barra lateral', () {
      expect(
        AdminSection.fromLocation('/admin/suporte/abc'),
        AdminSection.support,
      );
      expect(
        AdminSection.fromLocation('/admin/denuncias'),
        AdminSection.reports,
      );
      expect(
        AdminSection.fromLocation('/admin/avaliacoes'),
        AdminSection.ratings,
      );
      expect(AdminSection.fromLocation('/admin/registo'), AdminSection.log);
      expect(AdminSection.fromLocation('/admin'), AdminSection.overview);
    });

    test('app: cancelado pelo suporte', () {
      expect(
        CancelReason.label(CancelReason.support),
        'Cancelado pelo suporte',
      );
      expect(
        canRepublishJob(_job(cancelReason: CancelReason.support)),
        isFalse,
      );
      expect(canRepublishJob(_job(cancelReason: CancelReason.other)), isTrue);
      final m = inactiveJobMessage(
        cancelReason: CancelReason.support,
        cancelledByMe: false,
      );
      expect(m.title, 'O suporte cancelou este trabalho');
      expect(m.body, contains('Cancelado pelo suporte'));
    });

    test('app: aviso do suporte tem ícone próprio e conta como trabalho', () {
      final look = notificationLook(NotificationType.supportNotice);
      expect(look.icon, Icons.support_agent_rounded);
      expect(isJobNotification(NotificationType.supportNotice), isTrue);
    });
  });

  group('diálogo de ação', () {
    testWidgets('só confirma com motivo e nota, e passa o que se escreveu', (
      tester,
    ) async {
      _desktop(tester);
      AdminActionInput? got;
      var result = false;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showAdminActionDialog(
                  context,
                  icon: Icons.event_busy_outlined,
                  title: 'Cancelar pedido',
                  consequence: 'Recebem aviso: Ana e Rui.',
                  confirmLabel: 'Confirmar ação',
                  publicMessageLabel: 'Mensagem no aviso',
                  onSubmit: (input) async => got = input,
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Recebem aviso: Ana e Rui.'), findsOneWidget);

      bool enabled() =>
          tester
              .widget<ButtonStyleButton>(
                find.ancestor(
                  of: find.text('Confirmar ação'),
                  matching: find.bySubtype<ButtonStyleButton>(),
                ),
              )
              .onPressed !=
          null;

      expect(enabled(), isFalse);
      await tester.tap(find.text('Não cumpre os Termos'));
      await tester.pump();
      expect(enabled(), isFalse);
      await tester.enterText(find.byType(TextField).first, 'ok');
      await tester.pump();
      expect(enabled(), isFalse, reason: 'nota curta');
      await tester.enterText(
        find.byType(TextField).first,
        'Faltou duas vezes.',
      );
      await tester.enterText(find.byType(TextField).last, 'Lamentamos.');
      await tester.pump();
      expect(enabled(), isTrue);

      await tester.tap(find.text('Confirmar ação'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(got!.reason, AdminActionReason.termsViolation);
      expect(got!.note, 'Faltou duas vezes.');
      expect(got!.publicMessage, 'Lamentamos.');
    });

    testWidgets('erro do servidor fica no diálogo', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showAdminActionDialog(
                context,
                icon: Icons.visibility_outlined,
                title: 'Repor avaliação',
                consequence: 'Volta a aparecer.',
                confirmLabel: 'Repor',
                askReason: false,
                onSubmit: (_) async => throw const PostgrestException(
                  message: 'Avaliação oculta não encontrada.',
                  code: 'P0001',
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Não cumpre os Termos'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'Afinal está bem.');
      await tester.pump();
      await tester.tap(find.text('Repor'));
      await tester.pumpAndSettle();
      expect(find.text('Repor avaliação'), findsOneWidget);
      expect(find.textContaining('não encontrada'), findsOneWidget);
    });
  });

  group('vistas', () {
    testWidgets('caso: prazos, resposta e fechar só com decisão', (
      tester,
    ) async {
      _desktop(tester);
      AdminCaseStatus? setTo;
      String? decision;
      await tester.pumpWidget(
        _app(
          AdminCaseDetailView(
            detail: AdminCaseDetail.fromJson(
              _caseJson(firstReplyAt: '2026-11-16T11:00:00Z'),
            ),
            onOpen: (_) {},
            onAddNote: (_, _) async {},
            onSetStatus: (s, d) async {
              setTo = s;
              decision = d;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Caso #12 · Reporte de problema'), findsOneWidget);
      expect(find.text('Recebemos o teu reporte.'), findsOneWidget);
      expect(find.text('Resposta enviada'), findsOneWidget);
      expect(find.text('ana@exemplo.pt'), findsOneWidget);

      final close = find.widgetWithText(
        FilledButton,
        'Fechar com esta decisão',
      );
      expect(tester.widget<FilledButton>(close).onPressed, isNull);
      await tester.enterText(
        find.widgetWithText(TextField, 'Decisão fundamentada'),
        'Pedido cancelado; cliente avisada.',
      );
      await tester.pump();
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(setTo, AdminCaseStatus.resolved);
      expect(decision, 'Pedido cancelado; cliente avisada.');
    });

    testWidgets('ações do pedido aparecem pelo estado', (tester) async {
      _desktop(tester);
      final job = AdminJobDetail.fromJson({
        'job_id': 'j1',
        'status': 'completed',
        'service_name': 'Corte de relva',
        'client': {'id': 'c1', 'full_name': 'Ana Silva', 'deleted': false},
        'worker': {'id': 'w1', 'full_name': 'Rui Costa', 'deleted': false},
        'ratings': [
          {
            'id': 'rt1',
            'rater_name': 'Ana Silva',
            'stars': 1,
            'comment': 'Mau',
            'created_at': '2026-11-14T10:00:00Z',
          },
        ],
      });
      await tester.pumpWidget(_app(AdminJobActionsCard(job: job)));
      await tester.pumpAndSettle();
      expect(find.text('Anular a confirmação'), findsOneWidget);
      expect(find.text('Cancelar pedido'), findsNothing);
      expect(find.textContaining('"Mau"'), findsOneWidget);
      expect(find.text('Ocultar'), findsOneWidget);

      await tester.tap(find.text('Anular a confirmação'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ana Silva tem 7 dias novos'), findsOneWidget);
    });

    for (final width in [1400.0, 700.0]) {
      testWidgets('secções novas abrem sem erros de layout ($width px)', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final row = AdminCaseRow.fromJson(_caseJson());
        Widget page(String location, Widget child) =>
            AdminShell(location: location, child: child);
        final router = GoRouter(
          initialLocation: '/admin/suporte/$_caseId',
          routes: [
            GoRoute(
              path: '/admin/suporte/:id',
              builder: (_, state) => page(
                state.matchedLocation,
                AdminCasesPage(selectedCaseId: state.pathParameters['id']),
              ),
            ),
            GoRoute(
              path: '/admin/suporte',
              builder: (_, state) =>
                  page(state.matchedLocation, const AdminCasesPage()),
            ),
            GoRoute(
              path: '/admin/denuncias',
              builder: (_, state) =>
                  page(state.matchedLocation, const AdminReportsPage()),
            ),
            GoRoute(
              path: '/admin/avaliacoes',
              builder: (_, state) =>
                  page(state.matchedLocation, const AdminRatingsPage()),
            ),
            GoRoute(
              path: '/admin/registo',
              builder: (_, state) =>
                  page(state.matchedLocation, const AdminLogPage()),
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              adminCasesProvider.overrideWith((ref, _) async => [row]),
              adminCaseDetailProvider.overrideWith(
                (ref, _) async => AdminCaseDetail.fromJson(_caseJson()),
              ),
              adminReportsProvider.overrideWith(
                (ref, _) async => [
                  AdminReportRow.fromJson({
                    'report_id': 'r1',
                    'job_id': 'j1',
                    'service_name': 'Corte de relva',
                    'reporter_id': 'c1',
                    'reporter_name': 'Ana Silva',
                    'reporter_role': 'client',
                    'description': 'Não apareceu',
                    'status': 'new',
                    'created_at': '2026-11-16T09:00:00Z',
                    'due_at': '2026-11-18T09:00:00Z',
                    'total_count': 1,
                  }),
                ],
              ),
              adminRatingsProvider.overrideWith(
                (ref, _) async => [
                  AdminModerationRating.fromJson({
                    'rating_id': 'x',
                    'job_id': 'j1',
                    'rater_name': 'Ana Silva',
                    'ratee_name': 'Rui Costa',
                    'stars': 2,
                    'comment': 'Demorou',
                    'total_count': 1,
                  }),
                ],
              ),
              adminActionsProvider.overrideWith(
                (ref, _) async => [
                  AdminActionRow.fromJson({
                    'action_id': 'a1',
                    'action': 'hide_rating',
                    'admin_email': 'admin@projardim.pt',
                    'target_id': 'j1',
                    'details': {'reason': 'personal_data', 'note': 'Telefone.'},
                    'total_count': 1,
                  }),
                ],
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Caso #12 · Reporte de problema'), findsOneWidget);
        if (width < 1024) {
          await tester.tap(find.byTooltip('Voltar à lista'));
          await tester.pumpAndSettle();
        }
        expect(find.textContaining('1 reporte novo'), findsOneWidget);

        for (final (route, text) in [
          ('/admin/denuncias', 'Não apareceu'),
          ('/admin/avaliacoes', '"Demorou"'),
          ('/admin/registo', 'Dados pessoais expostos: Telefone.'),
        ]) {
          router.go(route);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: route);
          expect(find.text(text), findsOneWidget, reason: route);
        }
      });
    }
  });
}
