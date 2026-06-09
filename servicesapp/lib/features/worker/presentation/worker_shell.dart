import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class WorkerShell extends ConsumerWidget {
  const WorkerShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;

    final selectedIndex = _indexFromLocation(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          if (index == 2) {
            _showComingSoonSheet(context);
            return;
          }
          switch (index) {
            case 0:
              context.go('/worker/home');
            case 1:
              context.go('/worker/jobs');
            case 3:
              context.go('/worker/messages');
            case 4:
              context.go('/worker/profile');
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.work_outline),
            selectedIcon: Icon(Icons.work),
            label: 'Os meus jobs',
          ),
          NavigationDestination(
            icon: Icon(Icons.add),
            label: '+',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: 'Mensagens',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outlined),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  void _showComingSoonSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Em breve',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Brevemente poderás adicionar trabalhos externos e gerir a tua agenda aqui.',
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _indexFromLocation(String location) {
    if (location.startsWith('/worker/jobs')) return 1;
    if (location.startsWith('/worker/messages')) return 3;
    if (location.startsWith('/worker/profile')) return 4;
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
