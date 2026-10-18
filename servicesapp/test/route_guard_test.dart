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

String? _go(String loc, SessionStatus? session, {bool? seen = true}) =>
    resolveRedirect(location: loc, session: session, hasSeenOnboarding: seen);

void main() {
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

    test('rotas privadas mandam para o início', () {
      expect(_go('/client/home', anon), '/');
      expect(_go('/worker/setup', anon), '/');
      expect(_go('/choose-role', anon), '/');
      expect(_go('/notifications', anon), '/');
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
}
