import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_sizes.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_color.dart';

/// Sino do cabeçalho do Início, igual nos dois papéis (design U2): círculo
/// branco e um ponto vermelho quando há notificações por ler (sem número).
class HomeNotificationButton extends StatelessWidget {
  const HomeNotificationButton({
    super.key,
    required this.hasUnread,
    required this.onPressed,
  });

  final bool hasUnread;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: hasUnread ? 'Notificações, há novas' : 'Notificações',
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(side: BorderSide(color: AppColors.divider)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: AppSizes.headerIconButton,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: AppColors.textPrimary,
                ),
                if (hasUnread)
                  Positioned(
                    top: AppSpacing.s10,
                    right: AppSpacing.s10 + AppSpacing.xxs / 2,
                    child: Container(
                      width: AppSizes.unreadDot,
                      height: AppSizes.unreadDot,
                      decoration: BoxDecoration(
                        color: AppStatusColor.cancelled.foreground,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppColors.surface, width: 1.5),
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
