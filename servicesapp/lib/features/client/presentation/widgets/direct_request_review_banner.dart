import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_initials_avatar.dart';
import '../../../../core/widgets/app_motion.dart';

/// Faixa "Vai primeiro para ..." no passo 4 de "Criar pedido" (design A5,
/// 2). Vem com os dados da própria revisão: sem carregamento nem erro
/// próprios. Tom `info`: é informação do fluxo, não um estado do pedido.
class DirectRequestReviewBannerViewData {
  const DirectRequestReviewBannerViewData({
    required this.titleLabel,
    required this.descriptionLabel,
    required this.workerInitial,
    this.workerAvatarUrl,
  });

  final String titleLabel;

  /// Explicação das 24 horas, escrita pela integração.
  final String descriptionLabel;
  final String workerInitial;
  final String? workerAvatarUrl;
}

/// `data == null`: pedido normal, a faixa não aparece nem reserva espaço.
class DirectRequestReviewBanner extends StatelessWidget {
  const DirectRequestReviewBanner({
    super.key,
    required this.data,
    this.entranceIndex = 0,
  });

  final DirectRequestReviewBannerViewData? data;
  final int entranceIndex;

  @override
  Widget build(BuildContext context) {
    final value = data;
    if (value == null) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;
    const tone = AppStatusColor.info;

    return AppStaggeredEntrance(
      index: entranceIndex,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppInitialsAvatar(
              initial: value.workerInitial,
              avatarUrl: value.workerAvatarUrl,
              radius: AppSizes.directAvatarRadius,
              background: AppColors.surface,
              foreground: AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.titleLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: tone.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    value.descriptionLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
