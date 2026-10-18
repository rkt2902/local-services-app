import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/enums.dart';
import 'auth_providers.dart';
import '../../worker/application/worker_providers.dart';

class SessionStatus {
  final bool isLoading;
  final bool isAuthenticated;
  final UserRole? role;
  final bool workerProfileComplete;

  /// `true` quando há sessão mas o perfil (papel) não se conseguiu ler —
  /// tipicamente sem rede. Diferente de `role == null` com sucesso (conta
  /// nova, papel por escolher): aqui NÃO se pode mandar para
  /// `/choose-role`, onde escolher de novo reescreveria o perfil. O router
  /// manda para `/session-error`, com "Tentar novamente".
  final bool profileLoadFailed;

  const SessionStatus({
    this.isLoading = false,
    required this.isAuthenticated,
    required this.role,
    required this.workerProfileComplete,
    this.profileLoadFailed = false,
  });

  static const profileError = SessionStatus(
    isAuthenticated: true,
    role: null,
    workerProfileComplete: false,
    profileLoadFailed: true,
  );

  static const unauthenticated = SessionStatus(
    isAuthenticated: false,
    role: null,
    workerProfileComplete: false,
  );

  static const loading = SessionStatus(
    isLoading: true,
    isAuthenticated: false,
    role: null,
    workerProfileComplete: false,
  );
}

// Último estado resolvido com papel, guardado fora do notifier porque o
// Riverpod 3 recria o notifier a cada rebuild (invalidate no resume da app).
String? _lastResolvedUserId;
SessionStatus? _lastResolved;

class SessionNotifier extends AsyncNotifier<SessionStatus> {
  @override
  Future<SessionStatus> build() async {
    // Fast path: Supabase restores sessions from local storage during
    // initialize(), so currentSession is available immediately on app open.
    final currentSession = Supabase.instance.client.auth.currentSession;
    if (currentSession != null) {
      ref.watch(authStateProvider); // keep reactivity for logout/token refresh
      return _fetchProfile(currentSession.user.id);
    }

    // Slow path: no cached session — wait for the auth stream.
    final authState = ref.watch(authStateProvider);
    if (authState.isLoading) return SessionStatus.loading;
    final session = authState.value?.session;
    if (session == null) return SessionStatus.unauthenticated;
    return _fetchProfile(session.user.id);
  }

  Future<SessionStatus> _fetchProfile(String userId) async {
    try {
      final role =
          await ref.read(authRepositoryProvider).fetchUserRole(userId);
      bool workerComplete = false;
      if (role == UserRole.worker) {
        workerComplete =
            await ref.read(workerRepositoryProvider).hasProfile(userId);
      }
      final status = SessionStatus(
        isAuthenticated: true,
        role: role,
        workerProfileComplete: workerComplete,
      );
      if (role != null) {
        _lastResolvedUserId = userId;
        _lastResolved = status;
      }
      return status;
    } catch (_) {
      // Falha a ler o perfil (rede, timeout). Se este utilizador já tinha
      // papel resolvido nesta execução (ex.: a app voltou do fundo sem
      // rede), mantém-se o último valor: o papel não muda depois de
      // escolhido (trigger `prevent_profile_role_change`). Senão, estado
      // de erro, nunca `role: null` (isso mandava para /choose-role).
      if (_lastResolvedUserId == userId && _lastResolved != null) {
        return _lastResolved!;
      }
      return SessionStatus.profileError;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build());
  }
}

final sessionStatusProvider =
    AsyncNotifierProvider<SessionNotifier, SessionStatus>(
  SessionNotifier.new,
);
