import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/widgets/app_adaptive_shell.dart';
import '../../../core/widgets/app_bottom_navigation.dart';
import '../../agenda/presentation/agenda_entry_editor_screen.dart';
import '../../fleet_card/application/fleet_card_providers.dart';
import 'widgets/worker_quick_actions_sheet.dart';

class WorkerShell extends ConsumerWidget {
  const WorkerShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;

    final selectedIndex = _indexFromLocation(location);
    // Vigiado aqui (não só lido ao tocar no "+") para já estar carregado
    // quando a folha abre.
    final fleetActive =
        ref.watch(myFleetCardProvider).value?.status == FleetCardStatus.active;

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
      onCentralActionPressed: () =>
          _showQuickActionsSheet(context, fleetActive: fleetActive),
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

  /// Botão central: atalhos (design U2). A folha fecha antes de navegar,
  /// para a navegação nunca acontecer por baixo da modal. O Cartão frota só
  /// aparece com o cartão ativo.
  void _showQuickActionsSheet(BuildContext context,
      {required bool fleetActive}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (sheetContext) => WorkerQuickActionsSheet(
        showFleetCard: fleetActive,
        onFindWork: () {
          Navigator.pop(sheetContext);
          context.go('/worker/available-jobs');
        },
        onOpenHelpRequests: () {
          Navigator.pop(sheetContext);
          context.push('/worker/help-requests');
        },
        onAddToAgenda: () async {
          Navigator.pop(sheetContext);
          final result = await context.push<AgendaEditorResult>(
            '/worker/agenda/new',
          );
          // A Agenda abre no dia guardado e realça o cartão.
          if (result != null && context.mounted) {
            context.go('/worker/jobs', extra: {'agendaResult': result});
          }
        },
        onOpenFleetCard: () {
          Navigator.pop(sheetContext);
          context.push('/worker/fleet-card');
        },
      ),
    );
  }

  /// Só cobre as rotas de topo (mesmo padrão do WorkerShell anterior): rotas
  /// de detalhe (job/proposta/help-requests) recaem no default (0).
  int _indexFromLocation(String location) {
    if (location.startsWith('/worker/available-jobs')) return 1;
    if (location.startsWith('/worker/jobs')) return 2;
    if (location.startsWith('/worker/profile')) return 3;
    return 0;
  }
}
