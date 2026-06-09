import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/application/session_provider.dart';
import '../../features/auth/presentation/landing_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/choose_role_screen.dart';
import '../../features/client/presentation/client_home_screen.dart';
import '../../features/client/presentation/client_profile_screen.dart';
import '../../features/worker/presentation/worker_home_screen.dart';
import '../../features/jobs/presentation/create_job_screen.dart';
import '../../features/jobs/presentation/client_jobs_screen.dart';
import '../../features/jobs/presentation/client_job_detail_screen.dart';
import '../../features/jobs/data/job_model.dart';
import '../../features/worker/presentation/worker_profile_screen.dart';
import '../../features/worker/presentation/worker_setup_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);

  ref.listen(sessionStatusProvider, (prev, next) {
    // Only refresh router when session finishes loading (not while loading)
    if (!next.isLoading) refresh.value++;
  });

  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    refreshListenable: refresh,
    redirect: (context, state) {
      final sessionAsync = ref.read(sessionStatusProvider);
      final loc = state.matchedLocation;
      final publicRoutes = ['/', '/login', '/signup'];

      // While loading → don't redirect
      if (sessionAsync.isLoading) return null;
      final session = sessionAsync.value;
      if (session == null || session.isLoading) return null;

      // Not authenticated
      if (!session.isAuthenticated) {
        const unauthAllowed = ['/', '/login', '/signup', '/choose-role'];
        return unauthAllowed.contains(loc) ? null : '/';
      }

      // No role yet
      if (session.role == null) {
        const allowed = ['/choose-role', '/signup', '/login', '/'];
        return allowed.contains(loc) ? null : '/choose-role';
      }

      // Client
      if (session.role!.value == 'client') {
        if (loc.startsWith('/client/')) return null;
        if (publicRoutes.contains(loc) || loc == '/choose-role') {
          return '/client/home';
        }
        return null;
      }

      // Worker without profile
      if (!session.workerProfileComplete) {
        return loc == '/worker/setup' ? null : '/worker/setup';
      }

      // Worker with profile
      if (loc == '/worker/setup' ||
          publicRoutes.contains(loc) ||
          loc == '/choose-role') {
        return '/worker/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const LandingScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
      GoRoute(
        path: '/choose-role',
        builder: (context, state) {
          final extra = state.extra != null
              ? Map<String, String>.from(state.extra as Map)
              : null;
          return ChooseRoleScreen(
            fullName: extra?['fullName'] ?? '',
            phone: extra?['phone'] ?? '',
          );
        },
      ),
      GoRoute(path: '/worker/setup', builder: (_, _) => const WorkerSetupScreen()),
      GoRoute(path: '/client/home', builder: (_, _) => const ClientHomeScreen()),
      GoRoute(path: '/client/profile', builder: (_, _) => const ClientProfileScreen()),
      GoRoute(path: '/client/create-job', builder: (_, _) => const CreateJobScreen()),
      GoRoute(path: '/client/jobs', builder: (_, _) => const ClientJobsScreen()),
      GoRoute(
        path: '/client/job/:id',
        builder: (_, state) {
          final job = state.extra! as JobRequest;
          return ClientJobDetailScreen(job: job);
        },
      ),
      GoRoute(path: '/worker/home', builder: (_, _) => const WorkerHomeScreen()),
      GoRoute(path: '/worker/profile', builder: (_, _) => const WorkerProfileScreen()),
    ],
  );
});
