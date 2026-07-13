import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';

/// Badge de estado partilhado por toda a aplicação.
///
/// Para estados funcionais, usar sempre [AppStatusColor].
///
/// Exemplo:
///
/// ```dart
/// AppStatusBadge(
///   label: 'Em andamento',
///   statusColor: AppStatusColor.inProgress,
/// )
/// ```
///
/// Para estados neutros:
///
/// ```dart
/// AppStatusBadge.neutral(
///   label: 'Expirado',
/// )
/// ```
class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({
    required this.label,
    required this.statusColor,
    super.key,
  }) : neutral = false;

  const AppStatusBadge.neutral({
    required this.label,
    super.key,
  })  : statusColor = null,
        neutral = true;

  final String label;
  final AppStatusColor? statusColor;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final backgroundColor = neutral
        ? AppColors.divider
        : statusColor!.background;

    final foregroundColor = neutral
        ? AppColors.textSecondary
        : statusColor!.foreground;

    return Semantics(
      label: 'Estado: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(
            AppRadius.pill,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelMedium?.copyWith(
            color: foregroundColor,
          ),
        ),
      ),
    );
  }
}
