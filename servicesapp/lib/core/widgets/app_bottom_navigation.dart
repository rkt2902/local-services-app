import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';

class AppBottomNavigationItem {
  const AppBottomNavigationItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Bottom navigation partilhada com quatro destinos e uma ação central.
///
/// A ação central é independente dos destinos e não altera automaticamente
/// o índice selecionado.
///
/// O widget não decide rotas. Todas as ações são devolvidas por callbacks.
class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    required this.items,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.onCentralActionPressed,
    super.key,
    this.centralActionIcon = Icons.add_rounded,
    this.centralActionTooltip = 'Nova ação',
  }) : assert(
          items.length == 4,
          'AppBottomNavigation requer exatamente quatro destinos.',
        );

  final List<AppBottomNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  final VoidCallback onCentralActionPressed;
  final IconData centralActionIcon;
  final String centralActionTooltip;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 96,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: AppSpacing.sm,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(
                      AppRadius.card,
                    ),
                    border: Border.all(
                      color: AppColors.divider,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.textPrimary.withValues(
                          alpha: 0.08,
                        ),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _AppBottomNavigationDestination(
                          item: items[0],
                          selected: selectedIndex == 0,
                          onPressed: () => onItemSelected(0),
                        ),
                      ),
                      Expanded(
                        child: _AppBottomNavigationDestination(
                          item: items[1],
                          selected: selectedIndex == 1,
                          onPressed: () => onItemSelected(1),
                        ),
                      ),
                      const SizedBox(width: 66),
                      Expanded(
                        child: _AppBottomNavigationDestination(
                          item: items[2],
                          selected: selectedIndex == 2,
                          onPressed: () => onItemSelected(2),
                        ),
                      ),
                      Expanded(
                        child: _AppBottomNavigationDestination(
                          item: items[3],
                          selected: selectedIndex == 3,
                          onPressed: () => onItemSelected(3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 0,
                child: Tooltip(
                  message: centralActionTooltip,
                  child: SizedBox(
                    width: 54,
                    height: 54,
                    child: FilledButton(
                      onPressed: onCentralActionPressed,
                      style: ButtonStyle(
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.zero,
                        ),
                        elevation: const WidgetStatePropertyAll(4),
                        shadowColor: WidgetStatePropertyAll(
                          AppColors.textPrimary.withValues(
                            alpha: 0.16,
                          ),
                        ),
                        backgroundColor:
                            WidgetStateProperty.resolveWith<Color>(
                          (states) {
                            if (states.contains(
                              WidgetState.pressed,
                            )) {
                              return AppColors.primaryPressed;
                            }

                            return AppColors.primary;
                          },
                        ),
                        foregroundColor:
                            const WidgetStatePropertyAll(
                          AppColors.surface,
                        ),
                        shape: const WidgetStatePropertyAll(
                          CircleBorder(),
                        ),
                      ),
                      child: Icon(
                        centralActionIcon,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppBottomNavigationDestination extends StatelessWidget {
  const _AppBottomNavigationDestination({
    required this.item,
    required this.selected,
    required this.onPressed,
  });

  final AppBottomNavigationItem item;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final contentColor = selected
        ? AppColors.primary
        : AppColors.textSecondary;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(
          AppRadius.input,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.xs,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected
                    ? item.selectedIcon
                    : item.icon,
                size: 22,
                color: contentColor,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium?.copyWith(
                  color: contentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
