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

/// Query de `/` (e de `/login`) com o destino original de quem abriu uma
/// rota privada sem sessão. Ex.: `/?from=%2Fclient%2Fjob%2F123`.
const returnToParam = 'from';

/// Rotas que nunca se guardam como destino: as de entrada/autenticação e
/// as de passagem. Voltar a elas depois do login não faz sentido (ou cria
/// um ciclo).
const _noReturnRoutes = {
  ...publicRoutes,
  '/loading',
  '/choose-role',
  sessionErrorRoute,
};

bool _keepsReturnTarget(String path) => !_noReturnRoutes.contains(path);

/// Destino guardado em `?from=` se for seguro ir para lá com esta sessão,
/// senão `null` (e o router segue para o início do papel).
///
/// Só aceita caminhos internos (`/...`, nunca `//host` nem um URL com
/// esquema), nunca rotas de entrada/autenticação, e só rotas do próprio
/// papel. Um jardineiro com o perfil incompleto vai sempre primeiro para
/// `/worker/setup`.
String? safeReturnTarget(String? from, SessionStatus session) {
  if (from == null || from.isEmpty) return null;
  if (!from.startsWith('/') || from.startsWith('//')) return null;
  final target = Uri.tryParse(from);
  if (target == null || target.hasScheme || target.hasAuthority) return null;
  final path = target.path;
  if (!_keepsReturnTarget(path)) return null;
  final role = session.role;
  if (!session.isAuthenticated || role == null) return null;
  if (role.value == 'client' && path.startsWith('/worker/')) return null;
  if (role.value == 'worker') {
    if (path.startsWith('/client/')) return null;
    if (!session.workerProfileComplete) return null;
  }
  return from;
}

/// Decisão de redirect do router, sem Riverpod nem `BuildContext`, para se
/// poder testar (`test/route_guard_test.dart`). `RouterNotifier.redirect`
/// lê os providers e delega aqui.
///
/// [session] `null` = sessão ainda a carregar. [hasSeenOnboarding] `null` =
/// flag do onboarding ainda a carregar. `null` no retorno = ficar onde está.
/// [uri] é o endereço completo (com query). Serve para guardar o destino
/// quando um visitante sem sessão abre uma rota privada (`/?from=...`) e
/// para lá voltar depois de entrar (ver [safeReturnTarget]). Sem ele, a
/// decisão usa só [location].
String? resolveRedirect({
  required String location,
  required SessionStatus? session,
  required bool? hasSeenOnboarding,
  Uri? uri,
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
    // Guarda o destino para voltar a ele depois do login.
    if (_keepsReturnTarget(loc)) {
      final target = uri?.toString() ?? loc;
      return '/?$returnToParam=${Uri.encodeComponent(target)}';
    }
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
    // Acabou de entrar vindo de uma rota privada: volta para lá.
    final target =
        safeReturnTarget(uri?.queryParameters[returnToParam], session);
    if (target != null) return target;
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
