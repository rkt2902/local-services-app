import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_adaptive_shell.dart';
import '../../../core/widgets/app_bottom_navigation.dart';

class WorkerShell extends ConsumerWidget {
  const WorkerShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;

    final selectedIndex = _indexFromLocation(location);

    return AppAdaptiveShell(
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
      onCentralActionPressed: () => _showQuickActionsSheet(context),
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
      child: child,
    );
  }

  /// Botão central: atalhos para encontrar trabalho. A sheet fecha antes
  /// de navegar, para a navegação nunca acontecer por baixo da modal.
  void _showQuickActionsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Encontrar trabalho',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.sm),
              _QuickActionTile(
                icon: Icons.search_rounded,
                title: 'Ver pedidos perto de ti',
                subtitle: 'Pedidos de clientes na tua zona',
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.go('/worker/available-jobs');
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              _QuickActionTile(
                icon: Icons.groups_outlined,
                title: 'Pedidos de ajuda',
                subtitle: 'Ajuda outros jardineiros nos trabalhos deles',
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('/worker/help-requests');
                },
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

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                    Text(
                      subtitle,
                      style: textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
