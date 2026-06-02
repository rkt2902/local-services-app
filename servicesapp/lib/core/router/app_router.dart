import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const _PlaceholderScreen(name: '/'),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const _PlaceholderScreen(name: '/login'),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const _PlaceholderScreen(name: '/signup'),
      ),
      GoRoute(
        path: '/choose-role',
        builder: (context, state) =>
            const _PlaceholderScreen(name: '/choose-role'),
      ),
      GoRoute(
        path: '/client/home',
        builder: (context, state) =>
            const _PlaceholderScreen(name: '/client/home'),
      ),
      GoRoute(
        path: '/worker/home',
        builder: (context, state) =>
            const _PlaceholderScreen(name: '/worker/home'),
      ),
    ],
  );
});

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Center(child: Text(name)),
    );
  }
}
