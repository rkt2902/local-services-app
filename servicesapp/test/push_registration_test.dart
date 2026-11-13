import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/auth/application/auth_providers.dart';
import 'package:servicesapp/features/auth/application/session_provider.dart';
import 'package:servicesapp/features/notifications/application/push_notification_service.dart';

class _FixedSession extends SessionNotifier {
  _FixedSession(this._status);
  final SessionStatus _status;
  @override
  Future<SessionStatus> build() async => _status;
}

Future<String?> _registrationUserFor(SessionStatus status) async {
  final container = ProviderContainer(overrides: [
    currentUserIdProvider.overrideWithValue('u1'),
    sessionStatusProvider.overrideWith(() => _FixedSession(status)),
  ]);
  addTearDown(container.dispose);
  await container.read(sessionStatusProvider.future);
  return container.read(pushRegistrationUserIdProvider);
}

void main() {
  test('conta nova sem papel: ainda não regista o token de push', () async {
    expect(
      await _registrationUserFor(
        const SessionStatus(
          isAuthenticated: true,
          role: null,
          workerProfileComplete: false,
        ),
      ),
      isNull,
    );
  });

  test('com papel escolhido: regista para o utilizador atual', () async {
    expect(
      await _registrationUserFor(
        const SessionStatus(
          isAuthenticated: true,
          role: UserRole.worker,
          workerProfileComplete: true,
        ),
      ),
      'u1',
    );
  });

  test('sem sessão: não regista', () async {
    expect(await _registrationUserFor(SessionStatus.unauthenticated), isNull);
  });
}
