import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'app_page_transitions.dart';
import '../theme/app_colors.dart';
import '../../features/auth/application/session_provider.dart';
import '../../features/auth/presentation/landing_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/choose_role_screen.dart';
import '../../features/auth/presentation/request_password_reset_screen.dart';
import '../../features/auth/presentation/password_reset_screen.dart';
import '../../features/auth/presentation/verify_email_screen.dart';
import '../../features/auth/presentation/email_confirmed_screen.dart';
import '../../features/client/presentation/client_shell.dart';
import '../../features/client/presentation/client_home_screen.dart';
import '../../features/client/presentation/client_profile_screen.dart';
import '../../features/client/presentation/client_edit_profile_screen.dart';
import '../../features/worker/presentation/worker_shell.dart';
import '../../features/worker/presentation/worker_dashboard_screen.dart';
import '../../features/worker/presentation/worker_available_jobs_screen.dart';
import '../../features/worker/presentation/worker_job_detail_screen.dart';
import '../../features/worker/presentation/worker_submit_proposal_screen.dart';
import '../../features/client/presentation/client_create_job_service_screen.dart';
import '../../features/client/presentation/client_create_job_schedule_screen.dart';
import '../../features/client/presentation/client_create_job_description_screen.dart';
import '../../features/client/presentation/client_create_job_review_screen.dart';
import '../../features/jobs/presentation/client_jobs_screen.dart';
import '../../features/jobs/presentation/client_job_detail_screen.dart';
import '../../features/jobs/presentation/client_job_confirmed_screen.dart';
import '../../features/jobs/presentation/client_rate_worker_screen.dart';
import '../../features/worker/presentation/worker_profile_screen.dart';
import '../../features/worker/presentation/worker_edit_profile_screen.dart';
import '../../features/worker/presentation/worker_public_profile_screen.dart';
import '../../features/worker/presentation/worker_jobs_screen.dart';
import '../../features/worker/presentation/worker_my_job_detail_screen.dart';
import '../../features/fleet_card/presentation/fleet_card_screen.dart';
import '../../features/fleet_card/presentation/fleet_card_scan_screen.dart';
import '../../features/fleet_card/presentation/fleet_card_confirm_data_screen.dart';
import '../../features/help_requests/presentation/worker_help_requests_lobby_screen.dart';
import '../../features/help_requests/presentation/worker_help_requests_screen.dart';
import '../../features/help_requests/presentation/apply_as_helper_screen.dart';
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
      // Fade-through, não shared-axis: chega sempre de /loading (só um
      // spinner, sem conteúdo real a "avançar de"), nunca de um passo
      // anterior com sentido de progressão — ver nota no relatório.
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => buildFadeThroughPage(
          context,
          state,
          const ProJardimOnboardingScreen(),
        ),
      ),
      GoRoute(path: '/', builder: (_, _) => const LandingScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      // Passos do fluxo de registo — sempre alcançados a partir do passo
      // anterior, nunca de um card de lista: shared-axis (docs/motion_spec.md
      // §4). '/' e '/login' ficam de fora de propósito: têm origens
      // semanticamente distintas (reset não-autenticado, logout, "voltar"),
      // sem um tipo único que sirva a todas.
      GoRoute(
        path: '/signup',
        pageBuilder: (context, state) =>
            buildSharedAxisPage(context, state, const SignupScreen()),
      ),
      GoRoute(
        path: '/choose-role',
        pageBuilder: (context, state) =>
            buildSharedAxisPage(context, state, const ChooseRoleScreen()),
      ),
      // Fluxo de recuperação de senha — 2 rotas só (Part 3): esta e
      // /forgot-password/reset. Os passos 2-4 (verificar código, nova
      // senha, confirmação) trocam-se dentro de PasswordResetScreen sem
      // navegação — ver o comentário nesse ficheiro.
      GoRoute(
        path: '/forgot-password/request',
        pageBuilder: (context, state) {
          final email = state.uri.queryParameters['email'];
          return buildSharedAxisPage(
            context,
            state,
            RequestPasswordResetScreen(prefilledEmail: email),
          );
        },
      ),
      GoRoute(
        path: '/forgot-password/reset',
        pageBuilder: (context, state) {
          final email = state.uri.queryParameters['email'] ?? '';
          return buildSharedAxisPage(
            context,
            state,
            PasswordResetScreen(email: email),
          );
        },
      ),
      // Preparação para confirmação de email — ver comentário no topo de
      // verify_email_screen.dart. Rotas públicas por serem alcançáveis com
      // ou sem sessão (deep link futuro pode chegar sem sessão nenhuma).
      GoRoute(
        path: '/verify-email',
        pageBuilder: (context, state) {
          final email = state.uri.queryParameters['email'] ?? '';
          return buildSharedAxisPage(
            context,
            state,
            VerifyEmailScreen(email: email),
          );
        },
      ),
      GoRoute(
        path: '/email-confirmed',
        pageBuilder: (context, state) {
          final params = state.uri.queryParameters;
          return buildSharedAxisPage(
            context,
            state,
            EmailConfirmedScreen(
              email: params['email'],
              tokenHash: params['token_hash'],
              token: params['token'],
            ),
          );
        },
      ),
      GoRoute(path: '/worker/setup', builder: (_, _) => const WorkerSetupScreen()),
      GoRoute(
        path: '/worker/profile/edit',
        builder: (_, _) => const WorkerEditProfileScreen(),
      ),
      // Fade-through: alcançado a partir de um ícone de sino em 4 ecrãs
      // diferentes, nunca de um card — destino sem relação direta com a
      // origem, exatamente o exemplo dado em docs/motion_spec.md §4.
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) =>
            buildFadeThroughPage(context, state, const NotificationsScreen()),
      ),
      // Rota pública — cartão digital partilhável do worker. Sem guard de
      // autenticação/role (ver publicPathPrefixes no redirect abaixo).
      GoRoute(
        path: '/w/:workerId',
        builder: (_, state) {
          final workerId = state.pathParameters['workerId']!;
          return WorkerPublicProfileScreen(workerId: workerId);
        },
      ),
      // Fora dos ShellRoutes de propósito — ecrãs de sub-fluxo (detalhe,
      // formulário, lobby), não devem mostrar a bottom nav persistente.
      GoRoute(
        path: '/client/profile/edit',
        builder: (_, _) => const ClientEditProfileScreen(),
      ),
      // Wizard "criar pedido" — 4 passos sempre sequenciais, cada um só
      // alcançado a partir do anterior: shared-axis. `fromReview=true`
      // (só passado pelos callbacks "Editar" da revisão, passo 4) mostra
      // o mesmo ecrã com os dados já preenchidos do wizard provider, mas
      // "Continuar" volta direto à revisão (context.pop) em vez de seguir
      // a sequência normal — ver client_create_job_review_screen.dart.
      GoRoute(
        path: '/client/create-job',
        pageBuilder: (context, state) => buildSharedAxisPage(
          context,
          state,
          ClientCreateJobServiceScreen(
            fromReview: state.uri.queryParameters['fromReview'] == 'true',
          ),
        ),
      ),
      GoRoute(
        path: '/client/create-job/schedule',
        pageBuilder: (context, state) => buildSharedAxisPage(
          context,
          state,
          ClientCreateJobScheduleScreen(
            fromReview: state.uri.queryParameters['fromReview'] == 'true',
          ),
        ),
      ),
      GoRoute(
        path: '/client/create-job/description',
        pageBuilder: (context, state) => buildSharedAxisPage(
          context,
          state,
          ClientCreateJobDescriptionScreen(
            fromReview: state.uri.queryParameters['fromReview'] == 'true',
          ),
        ),
      ),
      GoRoute(
        path: '/client/create-job/review',
        pageBuilder: (context, state) => buildSharedAxisPage(
          context,
          state,
          const ClientCreateJobReviewScreen(),
        ),
      ),
      // Origem ambígua: card de lista (client_home_screen,
      // client_jobs_screen) OU notificação. Default = container-transform
      // (o mais comum); notification_handler.dart passa
      // extra: {'entryTransition': 'sharedAxis'} para o caso de deep-link.
      GoRoute(
        path: '/client/job/:id',
        pageBuilder: (context, state) {
          final jobId = state.pathParameters['id']!;
          final child = ClientJobDetailScreen(jobId: jobId);
          return _entryTransitionHint(state) == 'sharedAxis'
              ? buildSharedAxisPage(context, state, child)
              : buildContainerTransformPage(context, state, child);
        },
      ),
      // Só alcançado a partir de client_job_detail_screen (aceitar
      // proposta) — sem card de lista nem notificação envolvidos.
      GoRoute(
        path: '/client/job/:id/confirmed',
        pageBuilder: (context, state) {
          final jobId = state.pathParameters['id']!;
          final workerId = state.uri.queryParameters['workerId']!;
          return buildSharedAxisPage(
            context,
            state,
            ClientJobConfirmedScreen(jobId: jobId, workerId: workerId),
          );
        },
      ),
      GoRoute(
        path: '/client/job/:id/rate-worker',
        pageBuilder: (context, state) {
          final jobId = state.pathParameters['id']!;
          final workerId = state.uri.queryParameters['workerId']!;
          return buildSharedAxisPage(
            context,
            state,
            ClientRateWorkerScreen(jobId: jobId, workerId: workerId),
          );
        },
      ),
      // Só alcançado a partir de worker_job_detail_screen (botão
      // "Propor-me") — sem outra origem.
      GoRoute(
        path: '/worker/job/:id/propose',
        pageBuilder: (context, state) {
          final jobId = state.pathParameters['id']!;
          return buildSharedAxisPage(
            context,
            state,
            WorkerSubmitProposalScreen(jobId: jobId),
          );
        },
      ),
      // Só alcançado a partir de notificações (helpRequestApproved,
      // helpWithdrew) — sem card in-app que abra este lobby diretamente.
      GoRoute(
        path: '/worker/job/:id/help-requests',
        pageBuilder: (context, state) {
          final jobId = state.pathParameters['id']!;
          return buildSharedAxisPage(
            context,
            state,
            WorkerHelpRequestsLobbyScreen(jobId: jobId),
          );
        },
      ),
      // Origem ambígua: card de lista (worker_dashboard_screen,
      // worker_available_jobs_screen) OU notificação. Mesmo mecanismo de
      // /client/job/:id acima.
      GoRoute(
        path: '/worker/job/:id',
        pageBuilder: (context, state) {
          final jobId = state.pathParameters['id']!;
          final child = WorkerJobDetailScreen(jobId: jobId);
          return _entryTransitionHint(state) == 'sharedAxis'
              ? buildSharedAxisPage(context, state, child)
              : buildContainerTransformPage(context, state, child);
        },
      ),
      // Origem ambígua: card de lista (worker_dashboard_screen,
      // worker_jobs_screen) OU notificação. Mesmo mecanismo.
      GoRoute(
        path: '/worker/my-job/:id',
        pageBuilder: (context, state) {
          final proposalId = state.pathParameters['id']!;
          final jobId = state.uri.queryParameters['jobId']!;
          final child = WorkerMyJobDetailScreen(
            proposalId: proposalId,
            jobId: jobId,
          );
          return _entryTransitionHint(state) == 'sharedAxis'
              ? buildSharedAxisPage(context, state, child)
              : buildContainerTransformPage(context, state, child);
        },
      ),
      // Origem ambígua em tipo (não em código): botões CTA (não são cards)
      // em worker_available_jobs_screen/worker_jobs_screen — nenhum deles
      // pede shared-axis nem container-transform — OU notificação, que
      // pede shared-axis (deep-link). Default = fade-through.
      GoRoute(
        path: '/worker/help-requests',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final child = WorkerHelpRequestsScreen(
            initialTabIndex: extra?['initialTabIndex'] as int? ?? 0,
          );
          return _entryTransitionHint(state) == 'sharedAxis'
              ? buildSharedAxisPage(context, state, child)
              : buildFadeThroughPage(context, state, child);
        },
      ),
      // Só alcançado a partir de um card na tab "Descobrir" de
      // worker_help_requests_screen — lista → detalhe, sem ambiguidade.
      GoRoute(
        path: '/worker/help-requests/:id/apply',
        pageBuilder: (context, state) {
          final helpRequestId = state.pathParameters['id']!;
          return buildContainerTransformPage(
            context,
            state,
            ApplyAsHelperScreen(helpRequestId: helpRequestId),
          );
        },
      ),
      // Cartão frota — 3 rotas fora do ShellRoute (sub-fluxo, sem bottom
      // nav): estado atual, tirar foto, confirmar dados extraídos por OCR.
      // Cadeia sequencial de fluxo único: shared-axis.
      GoRoute(
        path: '/worker/fleet-card',
        pageBuilder: (context, state) =>
            buildSharedAxisPage(context, state, const FleetCardScreen()),
      ),
      GoRoute(
        path: '/worker/fleet-card/scan',
        pageBuilder: (context, state) =>
            buildSharedAxisPage(context, state, const FleetCardScanScreen()),
      ),
      GoRoute(
        path: '/worker/fleet-card/confirm',
        pageBuilder: (context, state) {
          final params = state.uri.queryParameters;
          return buildSharedAxisPage(
            context,
            state,
            FleetCardConfirmDataScreen(
              initialBarcodeNumber: params['barcode'] ?? '',
              initialCustomerCardNumber: params['cardNumber'] ?? '',
              initialCardHolderName: params['holderName'] ?? '',
              barcodeWasRead: params['barcodeWasRead'] == 'true',
            ),
          );
        },
      ),
      ShellRoute(
        builder: (context, state, child) => ClientShell(child: child),
        routes: [
          GoRoute(path: '/client/home', builder: (_, _) => const ClientHomeScreen()),
          GoRoute(path: '/client/jobs', builder: (_, _) => const ClientJobsScreen()),
          GoRoute(path: '/client/profile', builder: (_, _) => const ClientProfileScreen()),
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
          GoRoute(path: '/worker/profile', builder: (_, _) => const WorkerProfileScreen()),
          GoRoute(
            path: '/worker/jobs',
            builder: (_, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return WorkerJobsScreen(
                highlightedJobId: extra?['highlightedJobId'] as String?,
                initialTab: extra?['initialTab'] as String?,
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
    if (!isAuthenticated && !loc.startsWith('/w/')) {
      final onboardingAsync = _ref.read(hasSeenOnboardingProvider);
      if (onboardingAsync.isLoading) return null;
      final hasSeen = onboardingAsync.asData?.value ?? false;
      if (!hasSeen && loc != '/onboarding') return '/onboarding';
    }

    if (!isAuthenticated) {
      const publicRoutes = [
        '/',
        '/login',
        '/signup',
        '/onboarding',
        '/forgot-password/request',
        '/forgot-password/reset',
        '/verify-email',
        '/email-confirmed',
      ];
      if (publicRoutes.contains(loc)) return null;
      // Cartão digital do worker — visível sem sessão (link/QR partilhado).
      if (loc.startsWith('/w/')) return null;
      return '/';
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
      // Isenções de sub-fluxo: um worker recém-registado com perfil ainda
      // incompleto passa por /verify-email antes de chegar a
      // /worker/setup — sem esta isenção o guard empurrava-o para
      // /worker/setup assim que sessionStatusProvider terminava de
      // recarregar (ver verify_email_screen.dart), fazendo o ecrã piscar
      // e desaparecer sozinho. /email-confirmed fica isento pela mesma
      // razão (alvo do deep link futuro, também alcançável nesta janela).
      const workerSetupExemptRoutes = [
        '/worker/setup',
        '/verify-email',
        '/email-confirmed',
      ];
      if (workerSetupExemptRoutes.contains(loc)) return null;
      return '/worker/setup';
    }

    return null;
  }
}

/// Hint opcional em `extra` para escolher a transição de entrada nas
/// rotas com mais de uma origem (docs/motion_spec.md §4 — um deep-link de
/// notificação pede shared-axis mesmo numa rota cujo default é
/// container-transform quando vem de um card). Ausente, não-Map, ou valor
/// desconhecido → null; cada rota decide o próprio default nesse caso.
String? _entryTransitionHint(GoRouterState state) {
  final extra = state.extra;
  if (extra is Map) return extra['entryTransition'] as String?;
  return null;
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
