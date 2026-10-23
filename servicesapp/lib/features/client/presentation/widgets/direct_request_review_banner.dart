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
///
/// A7: com [releaseOptionTitleLabel] aparece o interruptor "Se não puder,
/// mostrar a outros jardineiros". O valor vive no rascunho do wizard e vai
/// para o servidor (`direct_auto_release`), não só no Switch.
class DirectRequestReviewBannerViewData {
  const DirectRequestReviewBannerViewData({
    required this.titleLabel,
    required this.descriptionLabel,
    required this.workerInitial,
    this.workerAvatarUrl,
    this.releaseOptionTitleLabel,
    this.releaseOptionDescriptionLabel = '',
    this.allowAutomaticReleaseToAll = true,
  });

  final String titleLabel;

  /// Explicação das 24 horas, escrita pela integração.
  final String descriptionLabel;
  final String workerInitial;
  final String? workerAvatarUrl;

  /// `null` esconde o interruptor.
  final String? releaseOptionTitleLabel;

  /// Muda com o interruptor (ligado e desligado explicam coisas
  /// diferentes).
  final String releaseOptionDescriptionLabel;
  final bool allowAutomaticReleaseToAll;
}

/// `data == null`: pedido normal, a faixa não aparece nem reserva espaço.
class DirectRequestReviewBanner extends StatelessWidget {
  const DirectRequestReviewBanner({
    super.key,
    required this.data,
    this.entranceIndex = 0,
    this.onAutomaticReleaseChanged,
  });

  final DirectRequestReviewBannerViewData? data;
  final int entranceIndex;
  final ValueChanged<bool>? onAutomaticReleaseChanged;

  @override
  Widget build(BuildContext context) {
    final value = data;
    if (value == null) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;
    const tone = AppStatusColor.info;
    final releaseTitle = value.releaseOptionTitleLabel;

    return AppStaggeredEntrance(
      index: entranceIndex,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
            if (releaseTitle != null) ...[
              const SizedBox(height: AppSpacing.sm),
              const Divider(height: 1, color: AppColors.divider),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          releaseTitle,
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          value.releaseOptionDescriptionLabel,
                          style: textTheme.labelMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Switch(
                    value: value.allowAutomaticReleaseToAll,
                    onChanged: onAutomaticReleaseChanged,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
