import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_motion_tokens.dart';
import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_sizes.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';

class AppBottomNavigationItem {
  const AppBottomNavigationItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Número por ler (ex. Alertas). 0 esconde o contador.
  final int badgeCount;
}

/// Bottom navigation partilhada com quatro destinos e uma ação central.
/// O jardineiro pode ter um quinto (Parceiros, só quando há parceiros):
/// fica 2 à esquerda do "+" e 3 à direita, todos com a mesma largura, e o
/// "+" acompanha o espaço entre eles.
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
    this.centralActionActive = false,
  }) : assert(
         items.length == 4 || items.length == 5,
         'AppBottomNavigation requer quatro ou cinco destinos.',
       );

  final List<AppBottomNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  final VoidCallback onCentralActionPressed;
  final IconData centralActionIcon;
  final String centralActionTooltip;

  /// A folha da ação central está aberta: o botão passa a "✕" escuro
  /// (A10, M4), no mesmo sítio e tamanho.
  final bool centralActionActive;

  static const double _centralGap = 66;
  static const double _centralButtonSize = 54;

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
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.divider),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.textPrimary.withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i == 2) const SizedBox(width: _centralGap),
                        Expanded(
                          child: _AppBottomNavigationDestination(
                            item: items[i],
                            selected: selectedIndex == i,
                            compact: items.length > 4,
                            onPressed: () => onItemSelected(i),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Com 4 destinos fica ao centro; com 5, por cima do espaço
              // depois dos dois primeiros.
              LayoutBuilder(
                builder: (context, constraints) {
                  final slot =
                      (constraints.maxWidth - _centralGap) / items.length;
                  return Padding(
                    padding: EdgeInsets.only(
                      left: 2 * slot + (_centralGap - _centralButtonSize) / 2,
                    ),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Tooltip(
                        message: centralActionTooltip,
                        child: _CentralActionButton(
                          icon: centralActionIcon,
                          active: centralActionActive,
                          onPressed: onCentralActionPressed,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// FAB central (docs/motion_spec.md §3, "FAB '+'": scale(0.88) ao premir,
/// tokens `instant · standard`) — sempre ativo, feedback de toque não é
/// desligado por reduced motion (ver nota em primary_action_button.dart).
class _CentralActionButton extends StatefulWidget {
  const _CentralActionButton({
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onPressed;

  @override
  State<_CentralActionButton> createState() => _CentralActionButtonState();
}

class _CentralActionButtonState extends State<_CentralActionButton> {
  static const double _pressedScale = 0.88;

  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? _pressedScale : 1,
        duration: AppMotionDuration.instant,
        curve: AppMotionCurve.standard,
        child: SizedBox(
          width: AppBottomNavigation._centralButtonSize,
          height: AppBottomNavigation._centralButtonSize,
          child: FilledButton(
            onPressed: widget.onPressed,
            style: ButtonStyle(
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              elevation: const WidgetStatePropertyAll(4),
              shadowColor: WidgetStatePropertyAll(
                AppColors.textPrimary.withValues(alpha: 0.16),
              ),
              backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.pressed)) {
                  return widget.active
                      ? AppColors.textSecondary
                      : AppColors.primaryPressed;
                }

                return widget.active
                    ? AppColors.textPrimary
                    : AppColors.primary;
              }),
              foregroundColor: const WidgetStatePropertyAll(AppColors.surface),
              shape: const WidgetStatePropertyAll(CircleBorder()),
            ),
            // "+" ↔ "✕" com a mesma rotação curta; sem animação com
            // reduced motion (motion_spec §5).
            child: AnimatedSwitcher(
              duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                  ? Duration.zero
                  : AppMotionDuration.fast,
              switchInCurve: AppMotionCurve.standard,
              switchOutCurve: AppMotionCurve.standard,
              transitionBuilder: (child, animation) => RotationTransition(
                turns: Tween<double>(begin: 0.75, end: 1).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                widget.active ? Icons.close_rounded : widget.icon,
                key: ValueKey<bool>(widget.active),
                size: 28,
              ),
            ),
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
    this.compact = false,
  });

  final AppBottomNavigationItem item;
  final bool selected;
  final VoidCallback onPressed;

  /// Cinco destinos: o texto encolhe para caber em vez de cortar.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final contentColor = selected ? AppColors.primary : AppColors.textSecondary;

    // docs/motion_spec.md §3, "Bottom nav": ícone cruza outline→preenchido,
    // cor e peso do label animam em simultâneo. Reduced motion mantém a
    // mudança de cor/peso (é informação de estado) mas corta a transição
    // (§5) — duração zero em vez de fast.
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final transitionDuration = disableAnimations
        ? Duration.zero
        : AppMotionDuration.fast;

    return Semantics(
      button: true,
      selected: selected,
      label: item.badgeCount > 0
          ? '${item.label}, ${item.badgeCount} por ler'
          : item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.input),
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
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedSwitcher(
                    duration: transitionDuration,
                    switchInCurve: AppMotionCurve.standard,
                    switchOutCurve: AppMotionCurve.standard,
                    child: Icon(
                      selected ? item.selectedIcon : item.icon,
                      key: ValueKey<bool>(selected),
                      size: 22,
                      color: contentColor,
                    ),
                  ),
                  if (item.badgeCount > 0)
                    Positioned(
                      top: -AppSpacing.xxs,
                      right: -AppSpacing.xs,
                      child: _UnreadDot(count: item.badgeCount),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              AnimatedDefaultTextStyle(
                duration: transitionDuration,
                curve: AppMotionCurve.standard,
                style: (textTheme.labelMedium ?? const TextStyle()).copyWith(
                  color: contentColor,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                child: compact
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(item.label, maxLines: 1),
                      )
                    : Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Contador por ler no ícone de um destino (mesmo estilo do sino do
/// jardineiro, `HomeNotificationButton`).
class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(
        minWidth: AppSizes.unreadBadge,
        minHeight: AppSizes.unreadBadge,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppStatusColor.cancelled.foreground,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.surface, width: 1.5),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        style: textTheme.labelMedium?.copyWith(
          color: AppColors.surface,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}
