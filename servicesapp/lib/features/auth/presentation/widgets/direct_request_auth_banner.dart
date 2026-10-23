import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_initials_avatar.dart';
import '../../../jobs/application/direct_request_labels.dart';

/// Faixa do login e do registo quando se vem do cartão de um jardineiro
/// (A7): "Vais pedir orçamento a Rui".
class DirectRequestAuthBanner extends StatelessWidget {
  const DirectRequestAuthBanner({
    super.key,
    required this.workerName,
    required this.descriptionLabel,
    this.workerAvatarUrl,
  });

  final String workerName;
  final String? workerAvatarUrl;

  /// "Cria a conta e voltas logo ao pedido."
  final String descriptionLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const tone = AppStatusColor.info;
    final name = firstNameOr(workerName, 'este jardineiro');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          AppInitialsAvatar(
            initial: initialOf(workerName.isEmpty ? 'J' : workerName),
            avatarUrl: workerAvatarUrl,
            radius: AppSizes.directAvatarRadius,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vais pedir orçamento a $name',
                  style: textTheme.bodyMedium?.copyWith(
                    color: tone.foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  descriptionLabel,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
