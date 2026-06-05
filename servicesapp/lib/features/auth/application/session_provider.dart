import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final authState = ref.watch(authStateProvider);

    if (authState.isLoading) return SessionStatus.loading;

    final session = authState.value?.session;
    if (session == null) return SessionStatus.unauthenticated;

    final user = ref.read(currentUserProvider);
    if (user == null) return SessionStatus.unauthenticated;

    try {
      final role =
          await ref.read(authRepositoryProvider).fetchUserRole(user.id);
      bool workerComplete = false;
      if (role == UserRole.worker) {
        workerComplete =
            await ref.read(workerRepositoryProvider).hasProfile(user.id);
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
