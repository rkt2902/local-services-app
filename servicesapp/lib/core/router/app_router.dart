import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/auth/presentation/landing_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/choose_role_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    redirect: (context, state) async {
      final isAuthenticated = authState.value?.session != null;
      final isAuthRoute = ['/login', '/signup', '/choose-role', '/']
          .contains(state.matchedLocation);

      if (!isAuthenticated && !isAuthRoute) return '/';
      if (isAuthenticated && state.matchedLocation == '/') {
        final repo = ref.read(authRepositoryProvider);
        final user = ref.read(currentUserProvider);
        if (user == null) return '/';
        final role = await repo.fetchUserRole(user.id);
        if (role == null) return '/choose-role';
        return role.value == 'client' ? '/client/home' : '/worker/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const LandingScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
          path: '/signup', builder: (context, state) => const SignupScreen()),
      GoRoute(
        path: '/choose-role',
        builder: (context, state) {
          final extra = state.extra as Map<String, String>?;
          return ChooseRoleScreen(
            fullName: extra?['fullName'] ?? '',
            phone: extra?['phone'] ?? '',
          );
        },
      ),
      GoRoute(
        path: '/client/home',
        builder: (context, state) =>
            const _PlaceholderScreen(title: 'Cliente — Home'),
      ),
      GoRoute(
        path: '/worker/home',
        builder: (context, state) =>
            const _PlaceholderScreen(title: 'Jardineiro — Home'),
      ),
    ],
  );
});

class _PlaceholderScreen extends StatelessWidget {
  final String title;
  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
      ),
    );
  }
}
