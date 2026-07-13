import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';

/// Chip reutilizável para filtros simples.
///
/// Serve para filtros como:
/// - Categoria
/// - Distância
/// - Urgente
/// - Estado selecionado/não selecionado
///
/// Não deve ser usado para estados de negócio. Para isso, usar
/// AppStatusBadge.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    required this.label,
    required this.onPressed,
    super.key,
    this.selected = false,
    this.leadingIcon,
    this.trailingIcon,
    this.showCheckmark = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool showCheckmark;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final foregroundColor = selected
        ? AppColors.primary
        : AppColors.textSecondary;

    final backgroundColor = selected
        ? AppColors.primaryContainer
        : AppColors.surface;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: 44,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: selected
                    ? AppColors.primary
                    : AppColors.divider,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showCheckmark && selected) ...[
                  const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ] else if (leadingIcon != null) ...[
                  Icon(
                    leadingIcon,
                    size: 18,
                    color: foregroundColor,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    color: foregroundColor,
                  ),
                ),
                if (trailingIcon != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    trailingIcon,
                    size: 18,
                    color: foregroundColor,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
