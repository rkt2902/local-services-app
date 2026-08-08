import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_bottom_navigation.dart';

class ClientShell extends ConsumerWidget {
  const ClientShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;

    final selectedIndex = _indexFromLocation(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: AppBottomNavigation(
        selectedIndex: selectedIndex,
        onItemSelected: (index) {
          switch (index) {
            case 0:
              context.go('/client/home');
            case 1:
              context.go('/client/jobs');
            case 2:
              context.push('/notifications');
            case 3:
              context.go('/client/profile');
          }
        },
        onCentralActionPressed: () => context.push('/client/create-job'),
        centralActionTooltip: 'Criar pedido',
        items: const [
          AppBottomNavigationItem(
            label: 'Início',
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
          ),
          AppBottomNavigationItem(
            label: 'Pedidos',
            icon: Icons.list_alt_outlined,
            selectedIcon: Icons.list_alt_rounded,
          ),
          AppBottomNavigationItem(
            label: 'Alertas',
            icon: Icons.notifications_none_rounded,
            selectedIcon: Icons.notifications_rounded,
          ),
          AppBottomNavigationItem(
            label: 'Conta',
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
          ),
        ],
      ),
    );
  }

  int _indexFromLocation(String location) {
    if (location == '/client/jobs') return 1;
    if (location.startsWith('/notifications')) return 2;
    if (location.startsWith('/client/profile')) return 3;
    return 0;
  }
}

// ignore: unused_element
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: Text('Em breve.')),
      );
}
