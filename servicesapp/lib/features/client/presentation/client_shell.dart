import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_adaptive_shell.dart';
import '../../../core/widgets/app_bottom_navigation.dart';
import '../application/client_create_job_wizard_provider.dart';
import 'card_request_launcher.dart';

class ClientShell extends ConsumerStatefulWidget {
  const ClientShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends ConsumerState<ClientShell> {
  @override
  void initState() {
    super.initState();
    // Acabou de entrar ou criar conta a partir do cartão de um jardineiro
    // (A7): volta ao pedido para ele, uma vez.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) resumePendingCardRequest(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final location = GoRouterState.of(context).matchedLocation;

    final selectedIndex = _indexFromLocation(location);

    return AppAdaptiveShell(
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
      onCentralActionPressed: () {
        // Um "Pedir de novo" abandonado não segue para um pedido novo.
        ref.read(clientCreateJobWizardProvider.notifier).clearDirectWorker();
        context.push('/client/create-job');
      },
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
      child: child,
    );
  }

  int _indexFromLocation(String location) {
    if (location == '/client/jobs') return 1;
    if (location.startsWith('/notifications')) return 2;
    if (location.startsWith('/client/profile')) return 3;
    return 0;
  }
}
