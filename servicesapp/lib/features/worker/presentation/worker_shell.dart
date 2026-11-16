import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/widgets/app_adaptive_shell.dart';
import '../../../core/widgets/app_bottom_navigation.dart';
import '../../agenda/presentation/agenda_day_presenter.dart';
import '../../agenda/presentation/agenda_entry_editor_screen.dart';
import '../../fleet_card/application/fleet_card_providers.dart';
import '../../partners/application/partner_providers.dart';
import '../application/worker_providers.dart';
import 'widgets/worker_quick_actions_sheet.dart';

class WorkerShell extends ConsumerStatefulWidget {
  const WorkerShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WorkerShell> createState() => _WorkerShellState();
}

class _WorkerShellState extends ConsumerState<WorkerShell> {
  /// A folha do "+" está aberta: o botão central mostra "✕" (A10, M4).
  bool _quickActionsOpen = false;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    // Quinto botão "Parceiros" só quando há parceiros para mostrar (0082).
    final showPartners = ref.watch(hasPartnersProvider);
    // Plano novo (ex.: passou a Pro+): os códigos dos parceiros mudam.
    ref.listen(myWorkerPlanProvider.select((plan) => plan.asData?.value.tier), (
      previous,
      next,
    ) {
      if (partnersStaleAfterPlanChange(previous, next)) {
        ref.invalidate(partnersProvider);
      }
    });
    final routes = workerShellRoutes(showPartners: showPartners);
    final selectedIndex = workerShellIndex(location, routes);
    // Vigiado aqui (não só lido ao tocar no "+") para já estar carregado
    // quando a folha abre.
    final fleetActive =
        ref.watch(myFleetCardProvider).value?.status == FleetCardStatus.active;

    return AppAdaptiveShell(
      selectedIndex: selectedIndex,
      centralActionActive: _quickActionsOpen,
      onItemSelected: (index) => context.go(routes[index]),
      onCentralActionPressed: () =>
          _showQuickActionsSheet(context, fleetActive: fleetActive),
      items: [
        const AppBottomNavigationItem(
          label: 'Início',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home_rounded,
        ),
        const AppBottomNavigationItem(
          label: 'Pedidos',
          icon: Icons.work_outline_rounded,
          selectedIcon: Icons.work_rounded,
        ),
        const AppBottomNavigationItem(
          label: 'Trabalhos',
          icon: Icons.event_note_outlined,
          selectedIcon: Icons.event_note_rounded,
        ),
        if (showPartners)
          const AppBottomNavigationItem(
            label: 'Parceiros',
            icon: Icons.storefront_outlined,
            selectedIcon: Icons.storefront_rounded,
          ),
        const AppBottomNavigationItem(
          label: 'Perfil',
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
        ),
      ],
      child: widget.child,
    );
  }

  /// Botão central: atalhos (design U2). A folha fecha antes de navegar,
  /// para a navegação nunca acontecer por baixo da modal. O Cartão frota só
  /// aparece com o cartão ativo.
  Future<void> _showQuickActionsSheet(
    BuildContext context, {
    required bool fleetActive,
  }) async {
    setState(() => _quickActionsOpen = true);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
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
        onAddToAgenda: () {
          Navigator.pop(sheetContext);
          _openAgendaEditor(context, block: false);
        },
        onMarkUnavailable: () {
          Navigator.pop(sheetContext);
          _openAgendaEditor(context, block: true);
        },
        onOpenFleetCard: () {
          Navigator.pop(sheetContext);
          context.push('/worker/fleet-card');
        },
      ),
    );
    if (mounted) setState(() => _quickActionsOpen = false);
  }

  /// Formulário da Agenda com a data de hoje, em "Trabalho" ou
  /// "Indisponível". Ao guardar, a Agenda abre no dia guardado e realça o
  /// cartão.
  Future<void> _openAgendaEditor(
    BuildContext context, {
    required bool block,
  }) async {
    final result = await context.push<AgendaEditorResult>(
      Uri(
        path: '/worker/agenda/new',
        queryParameters: {
          'date': agendaDayKey(DateTime.now()),
          if (block) 'type': 'block',
        },
      ).toString(),
    );
    if (result != null && context.mounted) {
      context.go('/worker/jobs', extra: {'agendaResult': result});
    }
  }
}

/// Rotas dos botões do menu do jardineiro, pela ordem. "Parceiros" fica
/// antes do Perfil e só existe quando há parceiros.
List<String> workerShellRoutes({required bool showPartners}) => [
  '/worker/home',
  '/worker/available-jobs',
  '/worker/jobs',
  if (showPartners) '/worker/partners',
  '/worker/profile',
];

/// Botão selecionado. Só cobre as rotas de topo: rotas de detalhe
/// (job/proposta/help-requests) recaem no Início (0).
int workerShellIndex(String location, List<String> routes) {
  for (var i = routes.length - 1; i > 0; i--) {
    if (location.startsWith(routes[i])) return i;
  }
  return 0;
}
