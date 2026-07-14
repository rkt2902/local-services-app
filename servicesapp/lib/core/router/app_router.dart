import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../../features/auth/application/session_provider.dart';
import '../../features/auth/presentation/landing_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/choose_role_screen.dart';
import '../../features/client/presentation/client_shell.dart';
import '../../features/client/presentation/client_home_screen.dart';
import '../../features/client/presentation/client_profile_screen.dart';
import '../../features/worker/presentation/worker_shell.dart';
import '../../features/worker/presentation/worker_dashboard_screen.dart';
import '../../features/worker/presentation/worker_available_jobs_screen.dart';
import '../../features/worker/presentation/worker_job_detail_screen.dart';
import '../../features/worker/presentation/worker_submit_proposal_screen.dart';
import '../../features/jobs/presentation/create_job_screen.dart';
import '../../features/jobs/presentation/client_jobs_screen.dart';
import '../../features/jobs/presentation/client_job_detail_screen.dart';
import '../../features/worker/presentation/worker_profile_screen.dart';
import '../../features/worker/presentation/worker_jobs_screen.dart';
import '../../features/worker/presentation/worker_my_job_detail_screen.dart';
import '../../features/help_requests/presentation/worker_help_requests_lobby_screen.dart';
import '../../features/help_requests/presentation/worker_help_requests_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/worker/presentation/worker_setup_screen.dart';
import '../../features/onboarding/application/onboarding_providers.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';

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
              color: AppColors.primary,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => const ProJardimOnboardingScreen(),
      ),
      GoRoute(path: '/', builder: (_, _) => const LandingScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
      GoRoute(
        path: '/choose-role',
        builder: (_, _) => const ChooseRoleScreen(),
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
              final jobId = state.pathParameters['id']!;
              return ClientJobDetailScreen(jobId: jobId);
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
          GoRoute(path: '/worker/home', builder: (_, _) => const WorkerDashboardScreen()),
          GoRoute(
            path: '/worker/available-jobs',
            builder: (_, _) => const WorkerAvailableJobsScreen(),
          ),
          GoRoute(
            path: '/worker/job/:id',
            builder: (context, state) {
              final jobId = state.pathParameters['id']!;
              return WorkerJobDetailScreen(jobId: jobId);
            },
          ),
          GoRoute(
            path: '/worker/job/:id/propose',
            builder: (context, state) {
              final jobId = state.pathParameters['id']!;
              return WorkerSubmitProposalScreen(jobId: jobId);
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
              final proposalId = state.pathParameters['id']!;
              final jobId = state.uri.queryParameters['jobId']!;
              return WorkerMyJobDetailScreen(
                proposalId: proposalId,
                jobId: jobId,
              );
            },
          ),
          GoRoute(
            path: '/worker/job/:id/help-requests',
            builder: (context, state) {
              final jobId = state.pathParameters['id']!;
              return WorkerHelpRequestsLobbyScreen(jobId: jobId);
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
    // Pre-warm the onboarding flag and react to changes (e.g. after markSeen).
    _ref.listen(hasSeenOnboardingProvider, (prev, next) => notifyListeners());
  }

  String? redirect(BuildContext context, GoRouterState state) {
    final sessionAsync = _ref.read(sessionStatusProvider);
    final loc = state.matchedLocation;

    if (sessionAsync.isLoading) {
      // Return null unconditionally — stay on the current route.
      // Cold start: loc is '/loading', spinner stays while session resolves.
      // Mid-session: any token-refresh tick leaves the user exactly where they are.
      // Redirecting to /loading on a transient tick tears down the current widget
      // tree mid-flight (e.g. while ImagePicker or a network request is awaiting),
      // causing silent data loss with no error shown. An allowlist (loadingExempt)
      // is the wrong fix because it must be grown every time a new route adds an
      // OS async interaction — this unconditional null eliminates the class of bug.
      return null;
    }

    final session = sessionAsync.asData?.value;
    final isAuthenticated = session?.isAuthenticated ?? false;
    final role = session?.role;
    final workerProfileComplete = session?.workerProfileComplete ?? false;

    // Onboarding gate: only for unauthenticated visitors, shown at most once.
    // Authenticated users (with or without role) bypass this entirely — they
    // have already committed to the app; onboarding is for first-time visitors.
    if (!isAuthenticated) {
      final onboardingAsync = _ref.read(hasSeenOnboardingProvider);
      if (onboardingAsync.isLoading) return null;
      final hasSeen = onboardingAsync.asData?.value ?? false;
      if (!hasSeen && loc != '/onboarding') return '/onboarding';
    }

    if (!isAuthenticated) {
      const publicRoutes = ['/', '/login', '/signup', '/onboarding'];
      return publicRoutes.contains(loc) ? null : '/';
    }

    // Authenticated but no profile yet (fresh signup, role not chosen)
    if (role == null) {
      return loc == '/choose-role' ? null : '/choose-role';
    }

    // Cross-role guard: prevent client accessing worker routes and vice versa.
    // P6 (state.extra! crash on direct nav) means cross-role access currently
    // crashes before rendering — after P6 is fixed (ID-based routing) this
    // guard becomes the primary protection against silent wrong-role data.
    if (role.value == 'client' && loc.startsWith('/worker/')) {
      return '/client/home';
    }
    if (role.value == 'worker' && loc.startsWith('/client/')) {
      return '/worker/home';
    }

    if (loc == '/' || loc == '/loading' || loc == '/login' || loc == '/signup' ||
        loc == '/choose-role') {
      if (role.value == 'worker') {
        if (workerProfileComplete) return '/worker/home';
        return '/worker/setup';
      }
      return '/client/home';
    }

    if (role.value == 'worker' && !workerProfileComplete) {
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
