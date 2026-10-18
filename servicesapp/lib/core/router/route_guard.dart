import '../../features/auth/application/session_provider.dart';

/// Rotas abertas sem sessão (além do cartão público `/w/...`).
const publicRoutes = {
  '/',
  '/login',
  '/signup',
  '/onboarding',
  '/forgot-password/request',
  '/forgot-password/reset',
  '/verify-email',
};

/// Ecrã de erro quando há sessão mas o perfil não se conseguiu ler.
const sessionErrorRoute = '/session-error';

/// Decisão de redirect do router, sem Riverpod nem `BuildContext`, para se
/// poder testar (`test/route_guard_test.dart`). `RouterNotifier.redirect`
/// lê os providers e delega aqui.
///
/// [session] `null` = sessão ainda a carregar. [hasSeenOnboarding] `null` =
/// flag do onboarding ainda a carregar. `null` no retorno = ficar onde está.
String? resolveRedirect({
  required String location,
  required SessionStatus? session,
  required bool? hasSeenOnboarding,
}) {
  final loc = location;
  // Sessão a carregar: ficar sempre onde está. Mandar para /loading num
  // refresh de token a meio da sessão destrói a árvore de widgets atual
  // (por exemplo com o ImagePicker aberto) e perde dados sem aviso.
  if (session == null) return null;

  final isAuthenticated = session.isAuthenticated;
  final role = session.role;

  // Onboarding: só para visitantes sem sessão, no máximo uma vez.
  if (!isAuthenticated && !loc.startsWith('/w/')) {
    if (hasSeenOnboarding == null) return null;
    if (!hasSeenOnboarding && loc != '/onboarding') return '/onboarding';
  }

  if (!isAuthenticated) {
    if (publicRoutes.contains(loc)) return null;
    // Cartão digital do worker, visível sem sessão (link/QR partilhado).
    if (loc.startsWith('/w/')) return null;
    return '/';
  }

  // Com sessão mas o perfil não carregou (rede): ecrã de erro com "Tentar
  // novamente", nunca /choose-role (reescreveria o perfil).
  if (session.profileLoadFailed) {
    return loc == sessionErrorRoute ? null : sessionErrorRoute;
  }

  // Com sessão mas sem perfil ainda (registo novo, papel por escolher).
  if (role == null) {
    return loc == '/choose-role' ? null : '/choose-role';
  }

  // Cada papel só nas suas rotas.
  if (role.value == 'client' && loc.startsWith('/worker/')) {
    return '/client/home';
  }
  if (role.value == 'worker' && loc.startsWith('/client/')) {
    return '/worker/home';
  }

  if (loc == '/' || loc == '/loading' || loc == '/login' || loc == '/signup' ||
      loc == '/choose-role' || loc == sessionErrorRoute) {
    if (role.value == 'worker') {
      return session.workerProfileComplete ? '/worker/home' : '/worker/setup';
    }
    return '/client/home';
  }

  if (role.value == 'worker' && !session.workerProfileComplete) {
    if (loc == '/worker/setup') return null;
    return '/worker/setup';
  }

  return null;
}
