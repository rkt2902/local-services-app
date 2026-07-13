import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_bottom_navigation.dart';

class WorkerShell extends ConsumerWidget {
  const WorkerShell({super.key, required this.child});

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
              context.go('/worker/home');
            case 1:
              context.go('/worker/available-jobs');
            case 2:
              context.go('/worker/jobs');
            case 3:
              context.go('/worker/profile');
          }
        },
        onCentralActionPressed: () => _showComingSoonSheet(context),
        items: const [
          AppBottomNavigationItem(
            label: 'Início',
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
          ),
          AppBottomNavigationItem(
            label: 'Pedidos',
            icon: Icons.work_outline_rounded,
            selectedIcon: Icons.work_rounded,
          ),
          AppBottomNavigationItem(
            label: 'Trabalhos',
            icon: Icons.event_note_outlined,
            selectedIcon: Icons.event_note_rounded,
          ),
          AppBottomNavigationItem(
            label: 'Perfil',
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
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

  /// Só cobre as rotas de topo (mesmo padrão do WorkerShell anterior): rotas
  /// de detalhe (job/proposta/help-requests) e "/worker/messages" (removida
  /// da bottom nav, mas a rota continua a existir) recaem no default (0).
  int _indexFromLocation(String location) {
    if (location.startsWith('/worker/available-jobs')) return 1;
    if (location.startsWith('/worker/jobs')) return 2;
    if (location.startsWith('/worker/profile')) return 3;
    return 0;
  }
}
