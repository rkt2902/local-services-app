import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_motion_tokens.dart';
import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';

/// Bloco de uma categoria de serviços (Jardinagem, Agricultura...) que abre
/// e fecha ao tocar no cabeçalho.
///
/// Fechado mostra só o ícone, o nome e um resumo ([summary], por exemplo
/// "3 de 13 selecionados"). Aberto mostra [child] (a grelha ou os chips dos
/// serviços) e, se houver [onSelectAll], um botão "Selecionar todos" /
/// "Limpar" para escolher a categoria inteira de uma vez.
///
/// Motion (docs/motion_spec.md §3): a altura cresce com `fast · standard` e
/// a seta roda; com reduced motion muda de estado sem animação.
class ServiceCategorySection extends StatelessWidget {
  const ServiceCategorySection({
    required this.icon,
    required this.title,
    required this.summary,
    required this.expanded,
    required this.onToggle,
    required this.child,
    super.key,
    this.highlighted = false,
    this.allSelected = false,
    this.onSelectAll,
  });

  final IconData icon;
  final String title;
  final String summary;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  /// Realça o cabeçalho quando a categoria tem serviços escolhidos.
  final bool highlighted;

  /// Estado do botão "Selecionar todos": `true` mostra "Limpar".
  final bool allSelected;

  /// `null` esconde o botão (escolha única, como no pedido do cliente).
  final ValueChanged<bool>? onSelectAll;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = disableAnimations ? Duration.zero : AppMotionDuration.fast;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: highlighted ? AppColors.primary : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
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
                            style: textTheme.titleSmall?.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            summary,
                            style: textTheme.labelMedium?.copyWith(
                              color: highlighted
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: duration,
                      curve: AppMotionCurve.standard,
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: duration,
            curve: AppMotionCurve.standard,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm,
                      0,
                      AppSpacing.sm,
                      AppSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (onSelectAll != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => onSelectAll!(!allSelected),
                              icon: Icon(
                                allSelected
                                    ? Icons.remove_done_rounded
                                    : Icons.done_all_rounded,
                                size: 18,
                              ),
                              label: Text(
                                allSelected ? 'Limpar' : 'Selecionar todos',
                              ),
                            ),
                          ),
                        child,
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
