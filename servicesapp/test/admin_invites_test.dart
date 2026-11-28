import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/router/route_guard.dart';
import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/widgets/primary_action_button.dart';
import 'package:servicesapp/features/admin/application/admin_labels.dart';
import 'package:servicesapp/features/admin/application/admin_providers.dart';
import 'package:servicesapp/features/admin/data/admin_invite_models.dart';
import 'package:servicesapp/features/admin/data/admin_invite_templates.dart';
import 'package:servicesapp/features/admin/data/admin_repository.dart';
import 'package:servicesapp/features/admin/presentation/admin_invites_page.dart';
import 'package:servicesapp/features/admin/presentation/admin_shell.dart';
import 'package:servicesapp/features/auth/application/session_provider.dart';
import 'package:servicesapp/features/invites/application/invite_optout_providers.dart';
import 'package:servicesapp/features/invites/data/invite_optout_repository.dart';
import 'package:servicesapp/features/invites/presentation/invite_optout_screen.dart';

// Convites por email no painel (0085). As RPCs (recusas, limite, repetidos,
// quem não quer receber) são testadas na BD
// (supabase/tests/audit/97_admin_invites.sql).

AdminInviteDraft _draft({
  AdminInviteTemplate template = AdminInviteTemplate.founderInvite,
  String name = 'Joaquim Sousa',
  String email = 'joaquim@example.com',
  String subject = 'Convite para Profissional fundador da ProJardim',
  String signedBy = 'Henrique',
  String term = '',
}) => AdminInviteDraft(
  template: template,
  recipientName: name,
  recipientEmail: email,
  subject: subject,
  signedBy: signedBy,
  founderTerm: term,
);

AdminInviteMessage _build(AdminInviteDraft d) => buildAdminInvite(
  d,
  siteUrl: 'https://projardim.pt',
  supportEmail: 'suporte@projardim.pt',
);

class _FakeRepo implements AdminRepository {
  AdminInviteEmailInfo info = const AdminInviteEmailInfo(
    optedOut: false,
    sentCount: 0,
    sentToday: 3,
    dailyLimit: 40,
  );
  final sent = <AdminInviteDraft>[];
  final optouts = <String>[];
  AdminInviteException? sendError;

  @override
  Future<AdminInviteEmailInfo> fetchInviteEmailInfo(String email) async => info;

  @override
  Future<void> sendInvite(AdminInviteDraft draft) async {
    if (sendError != null) throw sendError!;
    sent.add(draft);
  }

  @override
  Future<void> setInviteOptout(String email, {String? note}) async {
    optouts.add(email);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOptoutRepo implements InviteOptoutRepository {
  _FakeOptoutRepo(this.result);
  final bool result;
  final tokens = <String>[];

  @override
  Future<bool> optout(String token) async {
    tokens.add(token);
    return result;
  }
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('modelos de convite', () {
    test('cada modelo leva o marcador do link de deixar de receber, no HTML '
        'e no texto', () {
      for (final t in AdminInviteTemplate.values) {
        final m = _build(_draft(template: t));
        expect(
          m.toHtml(),
          contains(adminInviteOptoutPlaceholder),
          reason: '$t',
        );
        expect(
          m.toText(),
          contains(adminInviteOptoutPlaceholder),
          reason: '$t',
        );
        expect(m.toText(), contains(AdminInviteMessage.optoutLabel));
      }
    });

    test('o link real substitui o marcador', () {
      final m = _build(_draft());
      final html = m.toHtml(optoutUrl: 'https://projardim.pt/sem-convites?t=x');
      expect(html, contains('href="https://projardim.pt/sem-convites?t=x"'));
      expect(html, isNot(contains(adminInviteOptoutPlaceholder)));
    });

    test('nome, assinatura e contactos entram no texto', () {
      final text = _build(_draft()).toText();
      expect(text, startsWith('Bom dia, Joaquim Sousa.'));
      expect(text, contains('Henrique'));
      expect(text, contains('WhatsApp $adminInviteWhatsApp'));
      expect(text, contains('suporte@projardim.pt'));
      expect(text, contains('https://projardim.pt'));
      expect(text, isNot(contains('[Nome]')));
      expect(text, isNot(contains('[O seu nome]')));
    });

    test('o que o admin escreve é escapado no HTML', () {
      final html = _build(
        _draft(name: '<script>alert(1)</script>', signedBy: 'A & B'),
      ).toHtml();
      expect(html, isNot(contains('<script>')));
      expect(html, contains('&lt;script&gt;'));
      expect(html, contains('A &amp; B'));
    });

    test('duração do Pro de fundador: só aparece quando preenchida', () {
      final without = _build(_draft()).founderTitle;
      expect(without, 'Como fundador, tem o Plano Pro grátis.');
      final withTerm = _build(_draft(term: 'durante 12 meses'));
      expect(
        withTerm.founderTitle,
        'Como fundador, tem o Plano Pro grátis durante 12 meses.',
      );
      final plain = _build(
        _draft(
          template: AdminInviteTemplate.founderInvitePlain,
          term: 'durante 12 meses',
        ),
      ).toText();
      expect(plain, contains('com o Plano Pro grátis durante 12 meses.'));
    });

    test('o HTML usa as cores do design system', () {
      final html = _build(_draft()).toHtml();
      expect(cssHex(AppColors.primary), '#2E7D32');
      expect(html, contains('background:#2E7D32'));
      expect(html, contains(cssHex(AppColors.founderSurface)));
    });

    test('só texto e lembrete não têm topo verde nem botão', () {
      for (final t in [
        AdminInviteTemplate.founderInvitePlain,
        AdminInviteTemplate.founderReminder,
      ]) {
        final m = _build(_draft(template: t));
        expect(m.designed, isFalse);
        expect(m.ctaLabel, isNull);
        expect(m.toHtml(), isNot(contains(cssHex(AppColors.primary))));
      }
    });

    test('assuntos sugeridos usam o nome', () {
      final options = AdminInviteTemplate.founderInvite.subjectOptions('Rui');
      expect(options.first, 'Convite para Profissional fundador da ProJardim');
      expect(options, contains('Rui, gostávamos de o ter na ProJardim'));
      expect(
        AdminInviteTemplate.founderReminder.subjectOptions(''),
        contains('[Nome], teve oportunidade de ver o convite?'),
      );
    });

    test('fromDb', () {
      for (final t in AdminInviteTemplate.values) {
        expect(AdminInviteTemplate.fromDb(t.dbValue), t);
      }
      expect(AdminInviteTemplate.fromDb('outro'), isNull);
    });

    test('rascunho completo: nome, email válido, assunto e assinatura', () {
      expect(_draft().isComplete, isTrue);
      expect(_draft(email: 'sem-arroba').isComplete, isFalse);
      expect(_draft(email: 'a@b').isComplete, isFalse);
      expect(_draft(name: 'J').isComplete, isFalse);
      expect(_draft(signedBy: '').isComplete, isFalse);
      expect(_draft(subject: 'ab').isComplete, isFalse);
      expect(_draft(term: 'x' * 41).isComplete, isFalse);
    });
  });

  group('erros do envio', () {
    test('função por publicar, sem rede, sessão e recusas da BD', () {
      expect(adminInviteErrorMessage(404, null), contains('send-invite'));
      expect(adminInviteErrorMessage(0, null), contains('internet'));
      expect(adminInviteErrorMessage(401, null), contains('sessão'));
      expect(
        adminInviteErrorMessage(400, {
          'error': 'Este email pediu para não receber mais mensagens.',
        }),
        'Este email pediu para não receber mais mensagens.',
      );
      expect(
        adminInviteErrorMessage(502, {'error': 'Brevo 401: Key not found'}),
        contains('Ficou no histórico'),
      );
      expect(adminInviteErrorMessage(500, null), contains('500'));
    });
  });

  group('modelos da BD', () {
    test('linha do histórico', () {
      final row = AdminInviteRow.fromJson({
        'id': 'i1',
        'template': 'founder_reminder',
        'recipient_name': 'Rui',
        'recipient_email': 'rui@example.com',
        'subject': 'Assunto',
        'status': 'failed',
        'error': 'Brevo 401',
        'created_at': '2026-11-28T10:00:00Z',
        'opted_out_at': '2026-11-29T10:00:00Z',
        'total_count': 3,
      });
      expect(row.template, AdminInviteTemplate.founderReminder);
      expect(row.status, AdminInviteStatus.failed);
      expect(row.optedOut, isTrue);
      expect(row.totalCount, 3);
    });

    test('estado de um email', () {
      final info = AdminInviteEmailInfo.fromJson({
        'opted_out': false,
        'sent_count': 2,
        'last_sent_at': '2026-11-20T10:00:00Z',
        'last_template': 'founder_invite',
        'sent_today': 40,
        'daily_limit': 40,
      });
      expect(info.sentCount, 2);
      expect(info.lastTemplate, AdminInviteTemplate.founderInvite);
      expect(info.overDailyLimit, isTrue);
    });
  });

  group('painel', () {
    test('Convites na barra lateral', () {
      expect(
        AdminSection.fromLocation('/admin/convites'),
        AdminSection.invites,
      );
      expect(adminHistoryActionLabel('invite_create'), isNot('invite_create'));
      expect(adminHistoryActionLabel('invite_optout'), isNot('invite_optout'));
    });

    Future<_FakeRepo> pumpPage(
      WidgetTester tester, {
      List<AdminInviteRow> rows = const [],
    }) async {
      _tall(tester);
      final repo = _FakeRepo();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminRepositoryProvider.overrideWithValue(repo),
            adminInvitesProvider.overrideWith((ref, _) async => rows),
          ],
          child: const MaterialApp(home: Scaffold(body: AdminInvitesPage())),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    PrimaryActionButton sendButton(WidgetTester tester) =>
        tester.widget<PrimaryActionButton>(find.byType(PrimaryActionButton));

    testWidgets('pré-visualização segue o que se escreve e o envio pede '
        'confirmação', (tester) async {
      final repo = await pumpPage(tester);
      expect(sendButton(tester).onPressed, isNull);
      expect(find.text('Bom dia, [Nome].'), findsOneWidget);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Joaquim');
      await tester.enterText(fields.at(1), 'joaquim@example.com');
      await tester.enterText(fields.at(3), 'Henrique');
      await tester.pumpAndSettle();
      expect(find.text('Bom dia, Joaquim.'), findsOneWidget);
      expect(sendButton(tester).onPressed, isNotNull);

      await tester.tap(find.text('Rever e enviar'));
      await tester.pumpAndSettle();
      expect(find.text('Enviar para joaquim@example.com?'), findsOneWidget);
      expect(find.textContaining('Hoje: 3 de 40'), findsOneWidget);
      await tester.tap(find.text('Enviar'));
      await tester.pumpAndSettle();
      expect(repo.sent, hasLength(1));
      expect(repo.sent.single.recipientName, 'Joaquim');
      expect(repo.sent.single.template, AdminInviteTemplate.founderInvite);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('email que pediu para não receber: não chega a confirmar', (
      tester,
    ) async {
      final repo = await pumpPage(tester);
      repo.info = const AdminInviteEmailInfo(
        optedOut: true,
        sentCount: 1,
        sentToday: 0,
        dailyLimit: 40,
      );
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Joaquim');
      await tester.enterText(fields.at(1), 'joaquim@example.com');
      await tester.enterText(fields.at(3), 'Henrique');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rever e enviar'));
      await tester.pumpAndSettle();
      expect(find.text('Enviar para joaquim@example.com?'), findsNothing);
      expect(repo.sent, isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('histórico: lembrete preenche o formulário, "Não quer '
        'receber" regista', (tester) async {
      final repo = await pumpPage(
        tester,
        rows: [
          AdminInviteRow.fromJson({
            'id': 'i1',
            'template': 'founder_invite',
            'recipient_name': 'Rui Costa',
            'recipient_email': 'rui@example.com',
            'subject': 'Convite para Profissional fundador da ProJardim',
            'status': 'sent',
            'sent_at': '2026-11-20T10:00:00Z',
          }),
        ],
      );
      expect(find.text('rui@example.com'), findsOneWidget);
      await tester.ensureVisible(find.text('Lembrete').last);
      await tester.tap(find.text('Lembrete').last);
      await tester.pumpAndSettle();
      expect(find.text('Bom dia, Rui Costa.'), findsOneWidget);
      expect(
        find.text('Ainda tem lugar como Profissional fundador da ProJardim'),
        findsWidgets,
      );

      await tester.ensureVisible(find.text('Não quer receber'));
      await tester.tap(find.text('Não quer receber'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marcar'));
      await tester.pumpAndSettle();
      expect(repo.optouts, ['rui@example.com']);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('deixar de receber (/sem-convites)', () {
    test('abre sempre, com ou sem sessão, sem onboarding', () {
      expect(
        resolveRedirect(
          location: inviteOptoutRoute,
          session: const SessionStatus(
            isAuthenticated: false,
            role: null,
            workerProfileComplete: false,
          ),
          hasSeenOnboarding: false,
        ),
        isNull,
      );
    });

    test('token tem de parecer um uuid', () {
      expect(
        inviteOptoutTokenLooksValid('7c9e6679-7425-40de-944b-e07fc1f90ae7'),
        isTrue,
      );
      expect(inviteOptoutTokenLooksValid(null), isFalse);
      expect(inviteOptoutTokenLooksValid('abc'), isFalse);
    });

    Future<_FakeOptoutRepo> pumpScreen(
      WidgetTester tester, {
      String? token,
      bool result = true,
    }) async {
      final repo = _FakeOptoutRepo(result);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [inviteOptoutRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(home: InviteOptoutScreen(token: token)),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('confirma e mostra que ficou registado', (tester) async {
      const token = '7c9e6679-7425-40de-944b-e07fc1f90ae7';
      final repo = await pumpScreen(tester, token: token);
      await tester.tap(find.text('Não quero receber mais emails'));
      await tester.pumpAndSettle();
      expect(repo.tokens, [token]);
      expect(find.text('Pedido registado'), findsOneWidget);
    });

    testWidgets('token desconhecido: explica outra forma', (tester) async {
      await pumpScreen(
        tester,
        token: '7c9e6679-7425-40de-944b-e07fc1f90ae7',
        result: false,
      );
      await tester.tap(find.text('Não quero receber mais emails'));
      await tester.pumpAndSettle();
      expect(find.text('Link incompleto'), findsOneWidget);
    });

    testWidgets('sem token nem vai à BD', (tester) async {
      final repo = await pumpScreen(tester);
      expect(find.text('Link incompleto'), findsOneWidget);
      expect(repo.tokens, isEmpty);
    });
  });
}
