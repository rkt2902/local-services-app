import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/application/session_provider.dart';
import '../../features/auth/presentation/landing_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/choose_role_screen.dart';
import '../../features/client/presentation/client_shell.dart';
import '../../features/client/presentation/client_home_screen.dart';
import '../../features/client/presentation/client_profile_screen.dart';
import '../../features/worker/presentation/worker_shell.dart';
import '../../features/worker/presentation/worker_home_screen.dart';
import '../../features/worker/presentation/worker_job_detail_screen.dart';
import '../../features/jobs/presentation/create_job_screen.dart';
import '../../features/jobs/presentation/client_jobs_screen.dart';
import '../../features/jobs/presentation/client_job_detail_screen.dart';
import '../../features/jobs/data/job_model.dart';
import '../../features/worker/presentation/worker_profile_screen.dart';
import '../../features/worker/presentation/worker_jobs_screen.dart';
import '../../features/worker/presentation/worker_my_job_detail_screen.dart';
import '../../features/help_requests/presentation/worker_help_requests_lobby_screen.dart';
import '../../features/help_requests/presentation/worker_help_requests_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/worker/presentation/worker_setup_screen.dart';
import '../../features/proposals/data/proposal_model.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = RouterNotifier(ref);

  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/loading',
    debugLogDiagnostics: true,
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(
        path: '/loading',
        builder: (_, _) => const Scaffold(
          body: Center(
            child: CircularProgressIndicator(
              color: Color(0xFF2E7D32),
            ),
          ),
        ),
      ),
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
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
      ShellRoute(
        builder: (context, state, child) => ClientShell(child: child),
        routes: [
          GoRoute(path: '/client/home', builder: (_, _) => const ClientHomeScreen()),
          GoRoute(path: '/client/jobs', builder: (_, _) => const ClientJobsScreen()),
          GoRoute(
            path: '/client/job/:id',
            builder: (_, state) {
              final job = state.extra! as JobRequest;
              return ClientJobDetailScreen(job: job);
            },
          ),
          GoRoute(path: '/client/profile', builder: (_, _) => const ClientProfileScreen()),
          GoRoute(path: '/client/create-job', builder: (_, _) => const CreateJobScreen()),
          GoRoute(
            path: '/client/messages',
            builder: (_, _) => const _PlaceholderScreen('Mensagens'),
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) => WorkerShell(child: child),
        routes: [
          GoRoute(path: '/worker/home', builder: (_, _) => const WorkerHomeScreen()),
          GoRoute(
            path: '/worker/job/:id',
            builder: (context, state) {
              final job = state.extra! as JobRequest;
              return WorkerJobDetailScreen(job: job);
            },
          ),
          GoRoute(path: '/worker/profile', builder: (_, _) => const WorkerProfileScreen()),
          GoRoute(
            path: '/worker/jobs',
            builder: (_, _) => const WorkerJobsScreen(),
          ),
          GoRoute(
            path: '/worker/my-job/:id',
            builder: (context, state) {
              final extra = state.extra! as Map<String, dynamic>;
              return WorkerMyJobDetailScreen(
                proposal: extra['proposal'] as JobProposal,
                job: extra['job'] as JobRequest,
              );
            },
          ),
          GoRoute(
            path: '/worker/job/:id/help-requests',
            builder: (context, state) {
              final extra = state.extra! as Map<String, dynamic>;
              return WorkerHelpRequestsLobbyScreen(
                job: extra['job'] as JobRequest,
                proposal: extra['proposal'] as JobProposal,
              );
            },
          ),
          GoRoute(
            path: '/worker/help-requests',
            builder: (_, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return WorkerHelpRequestsScreen(
                initialTabIndex:
                    extra?['initialTabIndex'] as int? ?? 0,
              );
            },
          ),
          GoRoute(
            path: '/worker/messages',
            builder: (_, _) => const _PlaceholderScreen('Mensagens'),
          ),
        ],
      ),
    ],
  );
});

class RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  RouterNotifier(this._ref) {
    _ref.listen(sessionStatusProvider, (prev, next) => notifyListeners());
  }

  String? redirect(BuildContext context, GoRouterState state) {
    final sessionAsync = _ref.read(sessionStatusProvider);
    final loc = state.matchedLocation;

    if (sessionAsync.isLoading) {
      return loc == '/loading' ? null : '/loading';
    }

    final session = sessionAsync.asData?.value;
    final isAuthenticated = session?.isAuthenticated ?? false;
    final role = session?.role;
    final workerProfileComplete = session?.workerProfileComplete ?? false;

    if (!isAuthenticated) {
      const publicRoutes = ['/', '/login', '/signup'];
      return publicRoutes.contains(loc) ? null : '/';
    }

    if (loc == '/' || loc == '/loading' || loc == '/login' || loc == '/signup') {
      if (role?.value == 'worker') {
        if (workerProfileComplete) return '/worker/home';
        return '/worker/setup';
      }
      return '/client/home';
    }

    if (role?.value == 'worker' && !workerProfileComplete) {
      if (loc == '/worker/setup') return null;
      return '/worker/setup';
    }

    return null;
  }
}

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: Text('Em breve.')),
      );
}
