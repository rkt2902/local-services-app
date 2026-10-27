import 'package:flutter/material.dart';

import '../theme/app_breakpoints.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_sizes.dart';
import '../theme/app_spacing.dart';
import 'app_bottom_navigation.dart';
import 'app_brand_badge.dart';
import 'app_content_width.dart';
import 'app_motion.dart';

/// Scaffold dos 2 shells (cliente e jardineiro). Em telemóvel e tablet ao
/// alto mostra a [AppBottomNavigation] de sempre; a partir de
/// [AppBreakpoints.expanded] (tablet deitado, PC) troca-a por uma
/// [NavigationRail] à esquerda, com a marca e a ação central no topo, e
/// mantém o conteúdo centrado com [AppContentWidth] (que no telemóvel não
/// faz nada).
///
/// Os destinos e as ações são os mesmos nos dois modos: o shell não muda
/// de comportamento, só de disposição.
///
/// A navegação lateral exige também o lado menor do ecrã com pelo menos
/// [AppBreakpoints.compactShortestSide]: um telemóvel deitado (900 de
/// largura, 400 de altura) continua com a bottom nav. O conteúdo vai num
/// [GlobalKey] para não perder estado se o modo mudar (janela do PC
/// redimensionada, tablet rodado).
class AppAdaptiveShell extends StatefulWidget {
  const AppAdaptiveShell({
    super.key,
    required this.child,
    required this.items,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.onCentralActionPressed,
    this.centralActionTooltip = 'Nova ação',
    this.centralActionActive = false,
  });

  final Widget child;
  final List<AppBottomNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final VoidCallback onCentralActionPressed;
  final String centralActionTooltip;

  /// A folha da ação central está aberta ("+" vira "✕").
  final bool centralActionActive;

  @override
  State<AppAdaptiveShell> createState() => _AppAdaptiveShellState();
}

class _AppAdaptiveShellState extends State<AppAdaptiveShell> {
  final GlobalKey _contentKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final useRail = size.width >= AppBreakpoints.expanded &&
        size.shortestSide >= AppBreakpoints.compactShortestSide;
    final content = KeyedSubtree(
      key: _contentKey,
      child: AppContentWidth(child: widget.child),
    );
    if (!useRail) {
      return Scaffold(
        body: content,
        bottomNavigationBar: AppBottomNavigation(
          items: widget.items,
          selectedIndex: widget.selectedIndex,
          onItemSelected: widget.onItemSelected,
          onCentralActionPressed: widget.onCentralActionPressed,
          centralActionTooltip: widget.centralActionTooltip,
          centralActionActive: widget.centralActionActive,
        ),
      );
    }

    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: AppColors.surface,
            selectedIndex: widget.selectedIndex,
            onDestinationSelected: widget.onItemSelected,
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
            minWidth: AppSizes.railWidth,
            groupAlignment: -1,
            // Marca e "+" no topo, como no design U8; o "+" é quadrado de
            // cantos redondos com sombra, igual ao destaque da bottom nav.
            leading: Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.lg,
                bottom: AppSpacing.lg,
              ),
              child: Column(
                children: [
                  const AppStaggeredEntrance(
                    index: 0,
                    child: AppBrandBadge(
                      size: AppSizes.railBrand,
                      iconSize: AppSizes.rowIcon,
                      backgroundColor: AppColors.surface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppStaggeredEntrance(
                    index: 1,
                    child: Tooltip(
                      message: widget.centralActionTooltip,
                      child: Material(
                        color: widget.centralActionActive
                            ? AppColors.textPrimary
                            : AppColors.primary,
                        elevation: 4,
                        shadowColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.card),
                        ),
                        child: InkWell(
                          onTap: widget.onCentralActionPressed,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          child: SizedBox.square(
                            dimension: AppSizes.railAction,
                            child: Icon(
                              widget.centralActionActive
                                  ? Icons.close_rounded
                                  : Icons.add_rounded,
                              color: AppColors.surface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            destinations: [
              for (final item in widget.items)
                NavigationRailDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: Text(item.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1, color: AppColors.divider),
          Expanded(child: content),
        ],
      ),
    );
  }
}
