import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_sizes.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_color.dart';

/// Sino dos cabeçalhos do jardineiro (Início, Pedidos e Trabalhos, design
/// A11): o mesmo nos três, com o número de notificações por ler num círculo
/// vermelho. O cliente não tem sino: as notificações dele são o separador
/// Alertas.
class HomeNotificationButton extends StatelessWidget {
  const HomeNotificationButton({
    super.key,
    required this.unreadCount,
    required this.onPressed,
  });

  final int unreadCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final countLabel = unreadCount > 9 ? '9+' : '$unreadCount';

    return Semantics(
      button: true,
      label: unreadCount > 0
          ? 'Notificações, $unreadCount por ler'
          : 'Notificações',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: AppSizes.headerIconButton,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: AppColors.textPrimary,
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: AppSpacing.s6,
                    right: AppSpacing.s6,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: AppSizes.unreadBadge,
                        minHeight: AppSizes.unreadBadge,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxs,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppStatusColor.cancelled.foreground,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border:
                            Border.all(color: AppColors.surface, width: 1.5),
                      ),
                      child: Text(
                        countLabel,
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.surface,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
