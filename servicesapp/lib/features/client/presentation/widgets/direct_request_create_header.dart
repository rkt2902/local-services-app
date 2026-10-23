import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_initials_avatar.dart';
import '../../../jobs/application/direct_request_labels.dart';
import '../../application/client_create_job_wizard_provider.dart';

/// Faixa "Pedido para Rui" nos 4 passos do pedido pelo cartão (A7).
class DirectRequestCreateHeader extends StatelessWidget {
  const DirectRequestCreateHeader({
    super.key,
    required this.workerName,
    this.workerAvatarUrl,
  });

  final String workerName;
  final String? workerAvatarUrl;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final name = firstNameOr(workerName, 'o jardineiro');

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppInitialsAvatar(
            initial: initialOf(workerName.isEmpty ? 'J' : workerName),
            avatarUrl: workerAvatarUrl,
            radius: AppSizes.directChipAvatarRadius,
            textStyle: textTheme.labelMedium,
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              'Pedido para $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A faixa por baixo da barra de passos, só num pedido pelo cartão.
class WizardCardRequestHeader extends ConsumerWidget {
  const WizardCardRequestHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wizard = ref.watch(clientCreateJobWizardProvider);
    if (!wizard.isCardRequest) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DirectRequestCreateHeader(
          workerName: wizard.directWorkerName,
          workerAvatarUrl: wizard.directWorkerAvatarUrl,
        ),
      ),
    );
  }
}
