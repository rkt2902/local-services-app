import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';
import 'package:servicesapp/core/theme/app_status_presentation.dart';

class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({
    required this.label,
    required this.statusColor,
    super.key,
  });

  AppStatusBadge.fromPresentation({
    required AppStatusPresentation presentation,
    super.key,
  })  : label = presentation.label,
        statusColor = presentation.color;

  final String label;
  final AppStatusColor statusColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: 'Estado: $label',
      child: Container(
        constraints: const BoxConstraints(
          minHeight: 28,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: statusColor.background,
          borderRadius: BorderRadius.circular(
            AppRadius.pill,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelMedium?.copyWith(
            color: statusColor.foreground,
          ),
        ),
      ),
    );
  }
}
