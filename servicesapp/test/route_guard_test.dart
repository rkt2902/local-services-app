import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/router/route_guard.dart';
import 'package:servicesapp/features/auth/application/session_provider.dart';

const _client = SessionStatus(
  isAuthenticated: true,
  role: UserRole.client,
  workerProfileComplete: false,
);
const _worker = SessionStatus(
  isAuthenticated: true,
  role: UserRole.worker,
  workerProfileComplete: true,
);
const _workerIncomplete = SessionStatus(
  isAuthenticated: true,
  role: UserRole.worker,
  workerProfileComplete: false,
);
const _noRole = SessionStatus(
  isAuthenticated: true,
  role: null,
  workerProfileComplete: false,
);

String? _go(String loc, SessionStatus? session, {bool? seen = true}) {
  final uri = Uri.parse(loc);
  return resolveRedirect(
    location: uri.path,
    session: session,
    hasSeenOnboarding: seen,
    uri: uri,
  );
}

String _from(String target) => '/?from=${Uri.encodeComponent(target)}';

void main() {
  group('volta do login Google/Facebook (deep link)', () {
    test('sai de /login-callback com ou sem sessão', () {
      expect(_go('/login-callback', null), '/');
      expect(_go('/login-callback', SessionStatus.unauthenticated), '/');
      expect(_go('/login-callback', _noRole), '/');
    });
  });

  group('painel de administração (/admin)', () {
    test('sem sessão fica no /admin (é o login), mesmo sem onboarding', () {
      expect(_go('/admin', SessionStatus.unauthenticated), isNull);
      expect(_go('/admin', SessionStatus.unauthenticated, seen: false), isNull);
    });

    test('subpáginas sem sessão voltam à entrada do painel', () {
      expect(_go('/admin/workers/abc', SessionStatus.unauthenticated), '/admin');
    });

    test('a conta de admin sem papel não vai para escolher papel', () {
      expect(_go('/admin', _noRole), isNull);
      expect(_go('/admin/workers/abc', _noRole), isNull);
    });

    test('clientes e jardineiros também ficam (o ecrã diz "Sem acesso")', () {
      expect(_go('/admin', _client), isNull);
      expect(_go('/admin', _worker), isNull);
    });

    test('caminhos parecidos não contam como admin', () {
      expect(isAdminLocation('/administrator'), isFalse);
      expect(isAdminLocation('/admin'), isTrue);
      expect(isAdminLocation('/admin/workers/1'), isTrue);
    });
  });

  group('sessão a carregar', () {
    test('fica sempre onde está', () {
      for (final loc in ['/loading', '/client/home', '/worker/jobs', '/login']) {
        expect(_go(loc, null), isNull, reason: loc);
      }
    });
  });

  group('sem sessão', () {
    const anon = SessionStatus.unauthenticated;

    test('primeira visita vai para o onboarding', () {
      expect(_go('/', anon, seen: false), '/onboarding');
      expect(_go('/login', anon, seen: false), '/onboarding');
      expect(_go('/onboarding', anon, seen: false), isNull);
    });

    test('flag do onboarding a carregar: espera', () {
      expect(_go('/', anon, seen: null), isNull);
    });

    test('rotas públicas abertas', () {
      for (final loc in publicRoutes) {
        expect(_go(loc, anon), isNull, reason: loc);
      }
    });

    test('cartão público /w/ abre mesmo sem onboarding visto', () {
      expect(_go('/w/abc', anon, seen: false), isNull);
      expect(_go('/w/abc', anon), isNull);
    });

    test('rotas privadas mandam para o início, guardando o destino', () {
      expect(_go('/client/home', anon), _from('/client/home'));
      expect(_go('/worker/setup', anon), _from('/worker/setup'));
      expect(_go('/notifications', anon), _from('/notifications'));
      expect(
        _go('/client/job/abc/confirmed?workerId=w1', anon),
        _from('/client/job/abc/confirmed?workerId=w1'),
      );
    });

    test('rotas de passagem não guardam destino', () {
      expect(_go('/choose-role', anon), '/');
      expect(_go('/loading', anon), '/');
      expect(_go('/session-error', anon), '/');
    });

    test('o início com destino guardado fica (sem ciclo)', () {
      expect(_go(_from('/client/home'), anon), isNull);
      expect(_go('/login?from=%2Fclient%2Fhome', anon), isNull);
    });
  });

  group('voltar ao destino depois de entrar', () {
    test('cliente vai para o destino guardado', () {
      expect(_go(_from('/client/job/abc'), _client), '/client/job/abc');
      expect(
        _go('/login?from=${Uri.encodeComponent('/client/job/abc')}', _client),
        '/client/job/abc',
      );
      expect(_go(_from('/notifications'), _client), '/notifications');
    });

    test('jardineiro vai para o destino guardado', () {
      expect(_go(_from('/worker/jobs'), _worker), '/worker/jobs');
    });

    test('destino de outro papel é ignorado', () {
      expect(_go(_from('/worker/jobs'), _client), '/client/home');
      expect(_go(_from('/client/job/abc'), _worker), '/worker/home');
    });

    test('jardineiro com perfil incompleto vai primeiro ao setup', () {
      expect(_go(_from('/worker/jobs'), _workerIncomplete), '/worker/setup');
    });

    test('destinos de entrada, externos ou estranhos são ignorados', () {
      for (final from in [
        '/login',
        '/signup',
        '/',
        '/loading',
        '/choose-role',
        '/verify-email?email=a',
        '//evil.com/x',
        'https://evil.com/client/home',
        'client/home',
        '',
      ]) {
        expect(_go(_from(from), _client), '/client/home', reason: from);
      }
    });

    test('sem papel ainda: escolhe o papel primeiro', () {
      expect(_go(_from('/client/home'), _noRole), '/choose-role');
    });
  });

  group('safeReturnTarget', () {
    test('mantém a query do destino', () {
      expect(
        safeReturnTarget('/client/job/abc/confirmed?workerId=w1', _client),
        '/client/job/abc/confirmed?workerId=w1',
      );
    });

    test('sem sessão nunca devolve destino', () {
      expect(
        safeReturnTarget('/client/home', SessionStatus.unauthenticated),
        isNull,
      );
    });
  });

  group('com sessão sem papel', () {
    test('vai sempre para /choose-role', () {
      expect(_go('/', _noRole), '/choose-role');
      expect(_go('/client/home', _noRole), '/choose-role');
      expect(_go('/verify-email', _noRole), '/choose-role');
      expect(_go('/choose-role', _noRole), isNull);
    });

    test('ignora o onboarding', () {
      expect(_go('/choose-role', _noRole, seen: false), isNull);
    });
  });

  group('com sessão mas perfil por carregar (rede)', () {
    const failed = SessionStatus.profileError;

    test('vai para /session-error, nunca para /choose-role', () {
      expect(_go('/loading', failed), '/session-error');
      expect(_go('/client/home', failed), '/session-error');
      expect(_go('/choose-role', failed), '/session-error');
      expect(_go('/session-error', failed), isNull);
    });

    test('depois de recuperar, sai de /session-error para o início', () {
      expect(_go('/session-error', _client), '/client/home');
      expect(_go('/session-error', _worker), '/worker/home');
      expect(_go('/session-error', _noRole), '/choose-role');
      expect(_go('/session-error', SessionStatus.unauthenticated), '/');
    });
  });

  group('cliente', () {
    test('entradas levam para /client/home', () {
      for (final loc in ['/', '/loading', '/login', '/signup', '/choose-role']) {
        expect(_go(loc, _client), '/client/home', reason: loc);
      }
    });

    test('não entra em rotas de jardineiro', () {
      expect(_go('/worker/home', _client), '/client/home');
      expect(_go('/worker/setup', _client), '/client/home');
    });

    test('rotas próprias e partilhadas ficam', () {
      expect(_go('/client/jobs', _client), isNull);
      expect(_go('/notifications', _client), isNull);
      expect(_go('/w/abc', _client), isNull);
    });
  });

  group('jardineiro', () {
    test('entradas levam para /worker/home', () {
      for (final loc in ['/', '/loading', '/login', '/signup', '/choose-role']) {
        expect(_go(loc, _worker), '/worker/home', reason: loc);
      }
    });

    test('não entra em rotas de cliente', () {
      expect(_go('/client/home', _worker), '/worker/home');
    });

    test('perfil incompleto fica preso no /worker/setup', () {
      expect(_go('/', _workerIncomplete), '/worker/setup');
      expect(_go('/worker/home', _workerIncomplete), '/worker/setup');
      expect(_go('/notifications', _workerIncomplete), '/worker/setup');
      expect(_go('/worker/setup', _workerIncomplete), isNull);
    });

    test('perfil completo pode voltar ao setup e às outras rotas', () {
      expect(_go('/worker/setup', _worker), isNull);
      expect(_go('/worker/jobs', _worker), isNull);
    });
  });

  group('recuperação de senha com sessão aberta pelo código', () {
    test('fica em /forgot-password/reset seja qual for o papel', () {
      for (final session in [
        _client,
        _worker,
        _workerIncomplete,
        _noRole,
        SessionStatus.profileError,
      ]) {
        expect(_go('/forgot-password/reset?email=a%40b.pt', session), isNull);
      }
    });
  });
}
