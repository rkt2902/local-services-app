import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_sizes.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_presentation.dart';
import 'app_status_badge.dart';

/// Linha de um pedido com o próximo passo (design U1). Ícone do serviço,
/// título com o estado curto ao lado e uma segunda linha:
/// - com ação ([needsAction]): fundo verde claro, ponto verde e o próximo
///   passo a verde (ex.: "Tens 2 propostas para ver.");
/// - sem ação: os metadados a cinza (ex.: "Qui, 23/10 · 9:00 com Rui").
///
/// Os textos chegam já prontos; quem monta a lista põe os pedidos com ação
/// primeiro e decide para onde o toque leva.
class NextStepRow extends StatelessWidget {
  const NextStepRow({
    super.key,
    required this.icon,
    required this.title,
    required this.status,
    required this.subtitle,
    required this.onPressed,
    this.needsAction = false,
  });

  final IconData icon;
  final String title;
  final AppStatusPresentation status;

  /// Próximo passo quando [needsAction], senão os metadados.
  final String subtitle;
  final VoidCallback onPressed;
  final bool needsAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: needsAction ? AppColors.primaryTint : AppColors.surface,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: AppSizes.rowIconBox,
                height: AppSizes.rowIconBox,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: needsAction
                      ? AppColors.primaryContainer
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
                child: Icon(
                  icon,
                  size: AppSizes.rowIcon,
                  color:
                      needsAction ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium
                                ?.copyWith(color: AppColors.textPrimary),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        AppStatusBadge(
                          label: shortStatusLabel(status.label),
                          statusColor: status.color,
                          dense: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: [
                        if (needsAction) ...[
                          Container(
                            width: AppSizes.statusDot,
                            height: AppSizes.statusDot,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s6),
                        ],
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: needsAction
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              fontWeight: needsAction
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
