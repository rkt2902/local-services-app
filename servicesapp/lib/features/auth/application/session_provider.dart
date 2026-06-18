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

  const SessionStatus({
    this.isLoading = false,
    required this.isAuthenticated,
    required this.role,
    required this.workerProfileComplete,
  });

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
      return SessionStatus(
        isAuthenticated: true,
        role: role,
        workerProfileComplete: workerComplete,
      );
    } catch (_) {
      return const SessionStatus(
        isAuthenticated: true,
        role: null,
        workerProfileComplete: false,
      );
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
