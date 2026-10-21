import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_sizes.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_color.dart';
import 'app_motion.dart';
import 'primary_action_button.dart';

/// Estado vazio do design (U1): ícone num círculo, título, texto e, se
/// houver, um botão. Só o conteúdo; quem o usa decide o scroll e o
/// centramento (ex.: listas com pull-to-refresh).
///
/// [tone] `null` usa as cores da marca (verde); para vazios sem nada a
/// fazer (ex.: histórico) passar [AppStatusColor.neutral].
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.action,
    this.tone,
  }) : assert(
          (actionLabel == null) == (onAction == null),
          'O botão precisa de texto e de callback, ou de nenhum dos dois.',
        );

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Ação própria quando o botão principal não serve (ex.: um TextButton).
  /// Ignorada se houver [actionLabel].
  final Widget? action;
  final AppStatusColor? tone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final background = tone?.background ?? AppColors.primaryContainer;
    final foreground = tone?.foreground ?? AppColors.primary;
    final label = actionLabel;
    final Widget? actionWidget = label != null
        ? ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AppSizes.emptyActionMinWidth,
              maxWidth: AppSizes.emptyActionMaxWidth,
            ),
            child: IntrinsicWidth(
              child: PrimaryActionButton(label: label, onPressed: onAction),
            ),
          )
        : action;

    return AppStaggeredEntrance(
      index: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: AppSizes.emptyIconCircle,
            height: AppSizes.emptyIconCircle,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: background, shape: BoxShape.circle),
            child: Icon(icon, color: foreground, size: AppSizes.emptyIcon),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style:
                textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          if (actionWidget != null) ...[
            const SizedBox(height: AppSpacing.md),
            actionWidget,
          ],
        ],
      ),
    );
  }
}
