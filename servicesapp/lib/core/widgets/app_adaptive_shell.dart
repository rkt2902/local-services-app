import 'package:flutter/material.dart';

import '../theme/app_breakpoints.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_bottom_navigation.dart';
import 'app_content_width.dart';

/// Scaffold dos 2 shells (cliente e jardineiro). Em telemóvel e tablet ao
/// alto mostra a [AppBottomNavigation] de sempre; a partir de
/// [AppBreakpoints.expanded] (tablet deitado, PC) troca-a por uma
/// [NavigationRail] à esquerda, com a ação central como botão no topo, e
/// mantém o conteúdo centrado com [AppContentWidth] (que no telemóvel não
/// faz nada).
///
/// Os destinos e as ações são os mesmos nos dois modos: o shell não muda
/// de comportamento, só de disposição.
class AppAdaptiveShell extends StatelessWidget {
  const AppAdaptiveShell({
    super.key,
    required this.child,
    required this.items,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.onCentralActionPressed,
    this.centralActionTooltip = 'Nova ação',
  });

  final Widget child;
  final List<AppBottomNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final VoidCallback onCentralActionPressed;
  final String centralActionTooltip;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < AppBreakpoints.expanded) {
      return Scaffold(
        body: AppContentWidth(child: child),
        bottomNavigationBar: AppBottomNavigation(
          items: items,
          selectedIndex: selectedIndex,
          onItemSelected: onItemSelected,
          onCentralActionPressed: onCentralActionPressed,
          centralActionTooltip: centralActionTooltip,
        ),
      );
    }

    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: AppColors.surface,
            selectedIndex: selectedIndex,
            onDestinationSelected: onItemSelected,
            labelType: NavigationRailLabelType.all,
            indicatorColor: AppColors.primaryContainer,
            selectedIconTheme: const IconThemeData(color: AppColors.primary),
            unselectedIconTheme: const IconThemeData(
              color: AppColors.textSecondary,
            ),
            selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: FloatingActionButton(
                elevation: 0,
                tooltip: centralActionTooltip,
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.surface,
                shape: const CircleBorder(),
                onPressed: onCentralActionPressed,
                child: const Icon(Icons.add_rounded),
              ),
            ),
            destinations: [
              for (final item in items)
                NavigationRailDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: Text(item.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1, color: AppColors.divider),
          Expanded(child: AppContentWidth(child: child)),
        ],
      ),
    );
  }
}
