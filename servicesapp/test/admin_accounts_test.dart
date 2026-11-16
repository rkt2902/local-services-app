import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/router/route_guard.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';
import 'package:servicesapp/features/admin/application/admin_labels.dart';
import 'package:servicesapp/features/admin/data/admin_account_models.dart';
import 'package:servicesapp/features/admin/presentation/admin_map_page.dart';
import 'package:servicesapp/features/admin/presentation/admin_shell.dart';
import 'package:servicesapp/features/admin/presentation/widgets/admin_account_actions.dart';
import 'package:servicesapp/features/auth/application/session_provider.dart';
import 'package:servicesapp/features/auth/data/account_status.dart';
import 'package:servicesapp/features/auth/presentation/account_suspended_screen.dart';

// Painel de admin para suporte, fase C (0080): conta suspensa na app,
// cartão "Conta" da ficha e mapa. As RPCs (recusas, efeitos, registo) são
// testadas na BD (supabase/tests/audit/70_admin_accounts.sql).

const _personId = '4f8f1350-f963-42bc-84e5-ff2172cd9934';

Map<String, dynamic> _accountJson({
  String? suspendedAt,
  String? closingAt,
  String? deletedAt,
  bool? emailConfirmed = true,
  String? blocker,
  bool isAdmin = false,
  String? avatar,
}) => {
  'id': _personId,
  'role': 'worker',
  'deleted_at': deletedAt,
  'suspended_at': suspendedAt,
  'suspended_reason': suspendedAt == null ? null : 'terms_violation',
  'suspended_message': suspendedAt == null ? null : 'Faltaste a 3 trabalhos.',
  'closing_at': closingAt,
  'closing_reason': closingAt == null ? null : 'terms_violation',
  'closing_message': null,
  'avatar_url': avatar,
  'portfolio': <String>[],
  'is_admin': isAdmin,
  'deletion_blocker': blocker,
  'jobs_in_progress': blocker == null ? 0 : 1,
  'email_masked': 'a***@exemplo.pt',
  'email_confirmed': emailConfirmed,
  'last_sign_in_at': '2026-11-15T10:00:00Z',
};

Widget _app(Widget child) => ProviderScope(
  child: MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

class _Calls {
  final List<String> log = [];
  VoidCallback cb(String name) =>
      () => log.add(name);
}

AdminAccountView _view(AdminAccountState a, _Calls calls) => AdminAccountView(
  account: a,
  onSuspend: calls.cb('suspend'),
  onReactivate: calls.cb('reactivate'),
  onScheduleClosure: calls.cb('closure'),
  onCancelClosure: calls.cb('cancelClosure'),
  onResendCode: calls.cb('resend'),
  onExport: calls.cb('export'),
  onErase: calls.cb('erase'),
  onHidePhoto: (url, {required avatar}) => calls.log.add('hide:$avatar'),
);

AdminMapPoint _point(
  String id,
  AdminMapKind kind,
  String status, {
  int? radius,
}) => AdminMapPoint(
  kind: kind,
  id: id,
  lat: 38.72,
  lng: -9.14,
  label: kind == AdminMapKind.job ? 'Lisboa' : 'Rui',
  status: status,
  radiusKm: radius,
  service: kind == AdminMapKind.job ? 'Corte de relva' : null,
  plan: kind == AdminMapKind.job ? null : 'pro',
);

void main() {
  group('conta suspensa na app', () {
    test('estado vazio (sem 0080 ou sem nada) é conta ativa', () {
      final s = MyAccountStatus.fromJson(const {});
      expect(s.isSuspended, isFalse);
      expect(MyAccountStatus.active.isSuspended, isFalse);
    });

    test('lê a suspensão e a mensagem, ignora mensagem vazia', () {
      final s = MyAccountStatus.fromJson(const {
        'suspended_at': '2026-11-16T10:00:00Z',
        'suspended_message': '  ',
        'closing_at': null,
      });
      expect(s.isSuspended, isTrue);
      expect(s.suspendedMessage, isNull);
    });

    const suspended = SessionStatus(
      isAuthenticated: true,
      role: UserRole.client,
      workerProfileComplete: false,
      suspended: true,
    );
    const client = SessionStatus(
      isAuthenticated: true,
      role: UserRole.client,
      workerProfileComplete: false,
    );
    String? go(String loc, SessionStatus s) => resolveRedirect(
      location: loc,
      session: s,
      hasSeenOnboarding: true,
      uri: Uri.parse(loc),
    );

    test('suspensa vai sempre para o ecrã e fica lá', () {
      expect(go('/client/home', suspended), accountSuspendedRoute);
      expect(go('/client/job/1', suspended), accountSuspendedRoute);
      expect(go('/', suspended), accountSuspendedRoute);
      expect(go(accountSuspendedRoute, suspended), isNull);
    });

    test('reativada sai do ecrã para o início', () {
      expect(go(accountSuspendedRoute, client), '/client/home');
    });

    test('o painel de admin não é afetado', () {
      expect(go('/admin', suspended), isNull);
    });

    test('o ecrã suspenso nunca fica como destino depois do login', () {
      expect(safeReturnTarget(accountSuspendedRoute, client), isNull);
    });

    testWidgets('mostra a mensagem do suporte e as quatro saídas', (
      tester,
    ) async {
      final calls = _Calls();
      await tester.pumpWidget(
        MaterialApp(
          home: AccountSuspendedView(
            supportMessage: 'Faltaste a três trabalhos marcados.',
            isChecking: false,
            onContactSupport: calls.cb('support'),
            onCheckAgain: calls.cb('check'),
            onSignOut: calls.cb('signOut'),
            onDeleteAccount: calls.cb('delete'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Conta suspensa'), findsOneWidget);
      expect(find.text('Faltaste a três trabalhos marcados.'), findsOneWidget);
      expect(find.textContaining('6 meses'), findsOneWidget);
      for (final label in [
        'Contactar suporte',
        'Verificar de novo',
        'Terminar sessão',
        'Eliminar conta',
      ]) {
        await tester.tap(find.text(label));
      }
      expect(calls.log, ['support', 'check', 'signOut', 'delete']);
    });

    testWidgets('sem mensagem, texto padrão', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccountSuspendedView(
            supportMessage: null,
            isChecking: true,
            onContactSupport: () {},
            onCheckAgain: () {},
            onSignOut: () {},
            onDeleteAccount: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('O suporte da ProJardim suspendeu a tua conta.'),
        findsOneWidget,
      );
      final check = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Verificar de novo'),
      );
      expect(check.onPressed, isNull);
    });
  });

  group('estado da conta no painel', () {
    test('lê o JSON de admin_get_account', () {
      final a = AdminAccountState.fromJson(
        _accountJson(suspendedAt: '2026-11-16T10:00:00Z'),
      );
      expect(a.isSuspended, isTrue);
      expect(a.suspendedReason, 'terms_violation');
      expect(a.emailConfirmed, isTrue);
      expect(a.hasClosing, isFalse);
    });

    test('selo: ativa, suspensa, encerramento, eliminada', () {
      AdminAccountState of(Map<String, dynamic> j) =>
          AdminAccountState.fromJson(j);
      expect(adminAccountStatus(of(_accountJson())).$1, 'Ativa');
      final s = adminAccountStatus(
        of(_accountJson(suspendedAt: '2026-11-16T10:00:00Z')),
      );
      expect(s.$1, startsWith('Suspensa desde'));
      expect(s.$2, AppStatusColor.cancelled);
      expect(
        adminAccountStatus(
          of(_accountJson(closingAt: '2026-12-16T10:00:00Z')),
        ).$1,
        'Encerra a 16/12/2026',
      );
      expect(
        adminAccountStatus(
          of(_accountJson(deletedAt: '2026-11-16T10:00:00Z')),
        ).$1,
        'Eliminada',
      );
    });

    test('ficheiros a apagar depois de eliminar, com o bucket', () {
      final f = AdminErasedFiles.fromJson(const {
        'avatars': ['abc.jpg'],
        'job_photos_folder': 'abc/',
        'job_photos': ['abc/j1/1.jpg'],
      });
      expect(
        f.asText,
        'avatars/abc.jpg\njob-photos/abc/ (pasta toda)\njob-photos/abc/j1/1.jpg',
      );
    });

    test('nome do ficheiro exportado', () {
      expect(
        adminExportFileName(_personId, DateTime(2026, 11, 6)),
        'projardim-dados-4f8f1350-2026-11-06.json',
      );
    });

    testWidgets('conta ativa: suspender, encerrar, exportar, eliminar', (
      tester,
    ) async {
      _desktop(tester);
      final calls = _Calls();
      await tester.pumpWidget(
        _app(_view(AdminAccountState.fromJson(_accountJson()), calls)),
      );
      expect(find.text('Reativar'), findsNothing);
      expect(find.text('Reenviar código'), findsNothing);
      for (final label in [
        'Suspender',
        'Encerrar em 30 dias',
        'Exportar dados',
        'Eliminar a pedido',
      ]) {
        await tester.tap(find.text(label));
      }
      expect(calls.log, ['suspend', 'closure', 'export', 'erase']);
    });

    testWidgets('suspensa: motivo, mensagem e reativar', (tester) async {
      _desktop(tester);
      final calls = _Calls();
      await tester.pumpWidget(
        _app(
          _view(
            AdminAccountState.fromJson(
              _accountJson(suspendedAt: '2026-11-16T10:00:00Z'),
            ),
            calls,
          ),
        ),
      );
      expect(find.text('Motivo: Não cumpre os Termos'), findsOneWidget);
      expect(find.text('Mensagem: "Faltaste a 3 trabalhos."'), findsOneWidget);
      expect(find.text('Suspender'), findsNothing);
      expect(find.text('Encerrar em 30 dias'), findsNothing);
      await tester.tap(find.text('Reativar'));
      expect(calls.log, ['reactivate']);
    });

    testWidgets('encerramento marcado: cancelar; email por confirmar', (
      tester,
    ) async {
      _desktop(tester);
      final calls = _Calls();
      await tester.pumpWidget(
        _app(
          _view(
            AdminAccountState.fromJson(
              _accountJson(
                closingAt: '2026-12-16T10:00:00Z',
                emailConfirmed: false,
              ),
            ),
            calls,
          ),
        ),
      );
      expect(find.textContaining('(por confirmar)'), findsOneWidget);
      await tester.tap(find.text('Cancelar encerramento'));
      await tester.tap(find.text('Reenviar código'));
      expect(calls.log, ['cancelClosure', 'resend']);
    });

    testWidgets('trabalho em curso impede eliminar e diz porquê', (
      tester,
    ) async {
      _desktop(tester);
      await tester.pumpWidget(
        _app(
          _view(
            AdminAccountState.fromJson(
              _accountJson(blocker: 'Tens um trabalho em curso.'),
            ),
            _Calls(),
          ),
        ),
      );
      final erase = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Eliminar a pedido'),
          matching: find.byWidgetPredicate((w) => w is TextButton),
        ),
      );
      expect(erase.onPressed, isNull);
      expect(
        find.text('Para eliminar: Tens um trabalho em curso.'),
        findsOneWidget,
      );
    });

    testWidgets('conta de admin e conta eliminada não têm ações', (
      tester,
    ) async {
      _desktop(tester);
      await tester.pumpWidget(
        _app(
          _view(
            AdminAccountState.fromJson(_accountJson(isAdmin: true)),
            _Calls(),
          ),
        ),
      );
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Suspender'), findsNothing);

      final calls = _Calls();
      await tester.pumpWidget(
        _app(
          _view(
            AdminAccountState.fromJson(
              _accountJson(deletedAt: '2026-11-16T10:00:00Z'),
            ),
            calls,
          ),
        ),
      );
      expect(find.text('Suspender'), findsNothing);
      await tester.tap(find.text('Exportar o que resta'));
      expect(calls.log, ['export']);
    });

    testWidgets('foto de perfil com "Retirar"', (tester) async {
      _desktop(tester);
      final calls = _Calls();
      await tester.pumpWidget(
        _app(
          _view(
            AdminAccountState.fromJson(
              _accountJson(avatar: 'https://x.invalid/a.jpg'),
            ),
            calls,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Foto de perfil'), findsOneWidget);
      await tester.tap(find.text('Retirar'));
      expect(calls.log, ['hide:true']);
    });
  });

  group('mapa', () {
    final points = [
      _point('j1', AdminMapKind.job, 'open'),
      _point('j2', AdminMapKind.job, 'confirmed'),
      _point('j3', AdminMapKind.job, 'completed'),
      _point('w1', AdminMapKind.worker, 'active', radius: 25),
      _point('w2', AdminMapKind.worker, 'suspended', radius: 10),
    ];

    test('lê o JSON de admin_map_points', () {
      final p = AdminMapPoint.fromJson(const {
        'kind': 'worker',
        'id': 'w1',
        'lat': 41.15,
        'lng': -8.61,
        'radius_km': 15,
        'label': 'Rui',
        'status': 'active',
        'service': null,
        'plan': 'pro_plus',
        'created_at': '2026-10-01T10:00:00Z',
      });
      expect(p.isJob, isFalse);
      expect(p.radiusKm, 15);
      expect(adminPlanLabel(p.plan), 'Pro+');
    });

    test('camadas filtram os pontos', () {
      List<String> ids(Set<AdminMapLayer> l) =>
          adminVisibleMapPoints(points, l).map((p) => p.id).toList();
      expect(ids({AdminMapLayer.openJobs}), ['j1']);
      expect(ids({AdminMapLayer.activeJobs}), ['j2']);
      expect(ids({AdminMapLayer.doneJobs}), ['j3']);
      expect(ids({AdminMapLayer.workers}), ['w1', 'w2']);
      expect(ids({AdminMapLayer.radius}), isEmpty);
    });

    test('resumo conta cada tipo', () {
      expect(
        adminMapSummary(points),
        '1 pedidos abertos · 1 em curso · 1 concluídos (30 dias) · '
        '2 jardineiros (1 suspensos)',
      );
    });

    test('cores: suspenso a vermelho, aberto a azul', () {
      expect(adminMapPointTone(points[4]), AppStatusColor.cancelled);
      expect(adminMapPointTone(points[0]), AppStatusColor.info);
    });

    testWidgets('camadas e ficha do ponto escolhido', (tester) async {
      _desktop(tester);
      final toggled = <AdminMapLayer>[];
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminMapView(
              points: points,
              layers: const {AdminMapLayer.workers, AdminMapLayer.radius},
              selected: points[3],
              onToggle: toggled.add,
              onSelect: (_) {},
              onOpen: (p) => opened.add(p.id),
              onRefresh: () {},
              showTiles: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mapa'), findsOneWidget);
      await tester.tap(find.text('Pedidos abertos'));
      expect(toggled, [AdminMapLayer.openJobs]);
      expect(find.text('Rui'), findsOneWidget);
      expect(find.textContaining('raio 25 km'), findsOneWidget);
      await tester.tap(find.text('Abrir ficha'));
      expect(opened, ['w1']);
    });

    test('secção do Mapa na barra lateral', () {
      expect(AdminSection.fromLocation('/admin/mapa'), AdminSection.map);
    });
  });
}
