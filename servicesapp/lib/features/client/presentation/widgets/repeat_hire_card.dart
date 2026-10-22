import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_inline_error.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/user_avatar_with_name.dart';

/// Cartão "Precisas outra vez?" (design A5, 1) no fim do detalhe de um
/// trabalho concluído. Só contexto: o botão "Pedir de novo a ..." fica na
/// barra do fundo do ecrã (opção A do design, sem dois botões iguais).
class RepeatHireCardViewData {
  const RepeatHireCardViewData({
    required this.workerName,
    required this.previousJobLabel,
    required this.descriptionLabel,
    this.workerAvatarUrl,
  });

  final String workerName;
  final String? workerAvatarUrl;

  /// Serviço e data do último trabalho, já formatados.
  final String previousJobLabel;

  /// "Pede de novo e o pedido vai primeiro para Rui..." ou, sem perfil,
  /// "Este jardineiro já não aceita pedidos...".
  final String descriptionLabel;
}

/// `data == null`: o cartão não aparece. Erro: aviso pequeno com "Tentar
/// novamente", e o resto do detalhe continua.
class RepeatHireCard extends StatelessWidget {
  const RepeatHireCard({
    super.key,
    required this.dataAsync,
    this.onRetry,
    this.entranceIndex = 0,
  });

  final AsyncValue<RepeatHireCardViewData?> dataAsync;
  final VoidCallback? onRetry;
  final int entranceIndex;

  @override
  Widget build(BuildContext context) {
    return dataAsync.when(
      loading: () => const _RepeatHireSkeleton(),
      error: (_, _) => AppInlineError(
        message: 'Não foi possível carregar o jardineiro.',
        onRetry: onRetry,
      ),
      data: (data) {
        if (data == null) return const SizedBox.shrink();
        return AppStaggeredEntrance(
          index: entranceIndex,
          child: _RepeatHireLoaded(data: data),
        );
      },
    );
  }
}

class _RepeatHireLoaded extends StatelessWidget {
  const _RepeatHireLoaded({required this.data});

  final RepeatHireCardViewData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Precisas outra vez?',
            style: textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          UserAvatarWithName(
            name: data.workerName,
            avatarUrl: data.workerAvatarUrl,
            fallbackLabel: 'Jardineiro',
            subtitle: data.previousJobLabel,
            nameStyle: textTheme.titleSmall?.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            data.descriptionLabel,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RepeatHireSkeleton extends StatelessWidget {
  const _RepeatHireSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppSkeletonShimmer(
      child: Container(
        height: AppSizes.repeatHireSkeleton,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
    );
  }
}
