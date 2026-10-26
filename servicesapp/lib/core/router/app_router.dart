import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'app_page_transitions.dart';
import 'route_guard.dart';
import '../widgets/app_content_width.dart';
import '../../features/auth/application/session_provider.dart';
import '../../features/auth/presentation/landing_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/choose_role_screen.dart';
import '../../features/auth/presentation/request_password_reset_screen.dart';
import '../../features/auth/presentation/password_reset_screen.dart';
import '../../features/auth/presentation/verify_email_screen.dart';
import '../../features/auth/presentation/session_error_screen.dart';
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
import '../../features/jobs/presentation/client_proposal_detail_screen.dart';
import '../../features/jobs/presentation/client_proposals_screen.dart';
import '../../features/jobs/presentation/client_job_confirmed_screen.dart';
import '../../features/jobs/presentation/client_rate_worker_screen.dart';
import '../../features/jobs/presentation/client_edit_job_screen.dart';
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
import '../../features/help_requests/presentation/worker_helper_job_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/ratings/presentation/my_ratings_route.dart';
import '../../features/worker/presentation/worker_setup_screen.dart';
import '../../features/onboarding/application/onboarding_providers.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../widgets/app_launch_screen.dart';
import '../../features/agenda/application/agenda_entry_form.dart';
import '../../features/agenda/presentation/agenda_entry_editor_screen.dart';
import '../../features/admin/presentation/admin_gate_screen.dart';
import '../../features/admin/presentation/admin_worker_detail_screen.dart';

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
        builder: (_, _) => const AppLaunchScreen(),
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
      GoRoute(
        path: '/',
        builder: (_, _) => const AppContentWidth(child: LandingScreen()),
      ),
      GoRoute(
        path: '/login',
        builder: (_, _) => const AppContentWidth(child: LoginScreen()),
      ),
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
      // Sessão aberta mas o perfil não carregou (sem rede): ver
      // resolveRedirect em route_guard.dart.
      GoRoute(
        path: sessionErrorRoute,
        builder: (_, _) => const SessionErrorScreen(),
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
        path: '/worker/setup',
        builder: (_, _) => const AppContentWidth(child: WorkerSetupScreen()),
      ),
      GoRoute(
        path: '/worker/profile/edit',
        builder: (_, _) =>
            const AppContentWidth(child: WorkerEditProfileScreen()),
      ),
      // Fade-through: alcançado a partir de um ícone de sino em 4 ecrãs
      // diferentes, nunca de um card — destino sem relação direta com a
      // origem, exatamente o exemplo dado em docs/motion_spec.md §4.
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) =>
            buildFadeThroughPage(context, state, const NotificationsScreen()),
      ),
      // Mesma razão do fade-through de cima: "As minhas avaliações" é
      // alcançado a partir de um item de menu na conta (worker e cliente),
      // nunca de um card — sem relação direta de conteúdo com a origem.
      // Uma só rota/ecrã para os dois papéis: `MyRatingsRoute` não tem
      // nenhum código específico de cliente/worker (ver o seu doc comment).
      GoRoute(
        path: '/worker/ratings',
        pageBuilder: (context, state) =>
            buildFadeThroughPage(context, state, const MyRatingsRoute()),
      ),
      GoRoute(
        path: '/client/ratings',
        pageBuilder: (context, state) =>
            buildFadeThroughPage(context, state, const MyRatingsRoute()),
      ),
      // Painel de administração: fora dos papéis e dos ShellRoutes. O
      // ecrã de entrada trata do login e do segundo fator (ver
      // admin_gate_screen.dart); os dados só saem das RPCs admin_*.
      GoRoute(
        path: adminRoutePrefix,
        builder: (_, _) => const AppContentWidth(child: AdminGateScreen()),
      ),
      GoRoute(
        path: '$adminRoutePrefix/workers/:workerId',
        pageBuilder: (context, state) => buildSharedAxisPage(
          context,
          state,
          AdminWorkerDetailScreen(
            workerId: state.pathParameters['workerId']!,
          ),
        ),
      ),
      // Rota pública — cartão digital partilhável do worker. Sem guard de
      // autenticação/role (ver publicPathPrefixes no redirect abaixo).
      GoRoute(
        path: '/w/:workerId',
        builder: (_, state) {
          final workerId = state.pathParameters['workerId']!;
          return AppContentWidth(
            child: WorkerPublicProfileScreen(
              workerId: workerId,
              source: state.uri.queryParameters['src'],
            ),
          );
        },
      ),
      // Fora dos ShellRoutes de propósito — ecrãs de sub-fluxo (detalhe,
      // formulário, lobby), não devem mostrar a bottom nav persistente.
      GoRoute(
        path: '/client/profile/edit',
        builder: (_, _) =>
            const AppContentWidth(child: ClientEditProfileScreen()),
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
      // "Editar pedido": só a partir do botão no detalhe de um pedido
      // `open` (client_job_detail_screen). Passo de um fluxo: shared-axis.
      GoRoute(
        path: '/client/job/:id/edit',
        pageBuilder: (context, state) => buildSharedAxisPage(
          context,
          state,
          ClientEditJobScreen(jobId: state.pathParameters['id']!),
        ),
      ),
      // Só alcançado a partir de client_job_detail_screen (botão "Ver
      // propostas" no fundo do ecrã, ramo `open`) — sem card de lista nem
      // notificação envolvidos.
      GoRoute(
        path: '/client/job/:id/proposals',
        pageBuilder: (context, state) {
          final jobId = state.pathParameters['id']!;
          return buildSharedAxisPage(
            context,
            state,
            ClientProposalsScreen(jobId: jobId),
          );
        },
      ),
      // Detalhe de uma proposta e aceitação (design A6), a partir de
      // "Propostas recebidas".
      GoRoute(
        path: '/client/job/:id/proposals/:proposalId',
        pageBuilder: (context, state) {
          return buildSharedAxisPage(
            context,
            state,
            ClientProposalDetailScreen(
              jobId: state.pathParameters['id']!,
              proposalId: state.pathParameters['proposalId']!,
            ),
          );
        },
      ),
      // Só alcançado a partir de client_job_detail_screen (aceitar
      // proposta) — sem card de lista nem notificação envolvidos.
      GoRoute(
        path: '/client/job/:id/confirmed',
        // Sem `?workerId=` (link incompleto) vai para o detalhe do pedido,
        // que mostra o mesmo conteúdo, em vez de rebentar no `!`.
        redirect: _redirectWithoutWorkerId,
        pageBuilder: (context, state) {
          final jobId = state.pathParameters['id']!;
          final workerId = state.uri.queryParameters['workerId'] ?? '';
          return buildSharedAxisPage(
            context,
            state,
            ClientJobConfirmedScreen(jobId: jobId, workerId: workerId),
          );
        },
      ),
      GoRoute(
        path: '/client/job/:id/rate-worker',
        redirect: _redirectWithoutWorkerId,
        pageBuilder: (context, state) {
          final jobId = state.pathParameters['id']!;
          final workerId = state.uri.queryParameters['workerId'] ?? '';
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
      // Alcançado pelo cartão "Equipa" de worker_my_job_detail_screen
      // (extra `fromMyJob`) e por notificações (helpRequestApproved,
      // helpWithdrew).
      GoRoute(
        path: '/worker/job/:id/help-requests',
        pageBuilder: (context, state) {
          final jobId = state.pathParameters['id']!;
          final extra = state.extra;
          final fromMyJob = extra is Map && extra['fromMyJob'] == true;
          return buildSharedAxisPage(
            context,
            state,
            WorkerHelpRequestsLobbyScreen(jobId: jobId, fromMyJob: fromMyJob),
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
          // Sem `?jobId=` (link antigo/incompleto) o ecrã resolve o pedido a
          // partir da própria proposta, em vez de rebentar aqui.
          final jobId = state.uri.queryParameters['jobId'] ?? '';
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
      // Detalhe de uma candidatura vista pelo ajudante. Origem ambígua:
      // cartão (board, "As minhas candidaturas") OU notificação.
      GoRoute(
        path: '/worker/help/:acceptanceId',
        pageBuilder: (context, state) {
          final child = WorkerHelperJobScreen(
            acceptanceId: state.pathParameters['acceptanceId']!,
          );
          return _entryTransitionHint(state) == 'sharedAxis'
              ? buildSharedAxisPage(context, state, child)
              : buildContainerTransformPage(context, state, child);
        },
      ),
      // Agenda do jardineiro (0064): adicionar e editar trabalhos de fora da
      // app e indisponibilidades. Fora do ShellRoute (sub-fluxo, sem bottom
      // nav); abre de baixo e volta com um AgendaEditorResult. Origens: a
      // Agenda (Hoje, Semana, Mês) e o "+" central. `?date=` é o dia já
      // escolhido (novo) ou a ocorrência tocada (editar); `?type=block`
      // abre em Indisponível.
      GoRoute(
        path: '/worker/agenda/new',
        pageBuilder: (context, state) {
          final params = state.uri.queryParameters;
          return buildSlideUpPage<AgendaEditorResult>(
            context,
            state,
            AgendaEntryEditorScreen(
              initialDate: DateTime.tryParse(params['date'] ?? ''),
              initialType: params['type'] == 'block'
                  ? AgendaFormType.unavailable
                  : AgendaFormType.work,
            ),
          );
        },
      ),
      GoRoute(
        path: '/worker/agenda/:id',
        pageBuilder: (context, state) {
          return buildSlideUpPage<AgendaEditorResult>(
            context,
            state,
            AgendaEntryEditorScreen(
              entryId: state.pathParameters['id'],
              occurrenceDate: DateTime.tryParse(
                state.uri.queryParameters['date'] ?? '',
              ),
            ),
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
          // Sem /client/messages: não há mensagens dentro da app, o
          // contacto é só por WhatsApp.
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
                agendaResult: extra?['agendaResult'] as AgendaEditorResult?,
              );
            },
          ),
          // Sem /worker/messages: contacto só por WhatsApp.
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
    final session = sessionAsync.isLoading
        ? null
        : (sessionAsync.asData?.value ?? SessionStatus.unauthenticated);
    final onboardingAsync = _ref.read(hasSeenOnboardingProvider);
    final hasSeenOnboarding = onboardingAsync.isLoading
        ? null
        : (onboardingAsync.asData?.value ?? false);
    return resolveRedirect(
      location: state.matchedLocation,
      session: session,
      hasSeenOnboarding: hasSeenOnboarding,
      uri: state.uri,
    );
  }
}

/// Rotas de cliente que precisam de `?workerId=`: sem ele, vão para o
/// detalhe do próprio pedido.
String? _redirectWithoutWorkerId(BuildContext context, GoRouterState state) {
  final workerId = state.uri.queryParameters['workerId'] ?? '';
  if (workerId.isNotEmpty) return null;
  return '/client/job/${state.pathParameters['id']}';
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
