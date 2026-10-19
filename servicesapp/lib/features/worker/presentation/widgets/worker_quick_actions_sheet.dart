import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_motion.dart';

/// Folha do "+" do jardineiro (design U2): "O que queres fazer?" com os
/// atalhos. O Cartão frota só aparece quando o cartão está ativo
/// ([showFleetCard]). Não navega: cada callback fecha e decide o destino.
///
/// Sem [AppSheet] de propósito: aqui não há ação principal nem botão de
/// fechar, só a pega e cartões equivalentes.
class WorkerQuickActionsSheet extends StatelessWidget {
  const WorkerQuickActionsSheet({
    super.key,
    required this.onFindWork,
    required this.onOpenHelpRequests,
    required this.onOpenFleetCard,
    this.showFleetCard = false,
  });

  final VoidCallback onFindWork;
  final VoidCallback onOpenHelpRequests;
  final VoidCallback onOpenFleetCard;
  final bool showFleetCard;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final actions = [
      _QuickActionCard(
        icon: Icons.travel_explore_rounded,
        tone: AppStatusColor.success,
        title: 'Encontrar trabalho',
        subtitle: 'Ver pedidos perto de ti',
        onPressed: onFindWork,
      ),
      _QuickActionCard(
        icon: Icons.handshake_outlined,
        tone: AppStatusColor.info,
        title: 'Pedidos de ajuda',
        subtitle: 'Ajuda outros jardineiros nos trabalhos deles',
        onPressed: onOpenHelpRequests,
      ),
      if (showFleetCard)
        _QuickActionCard(
          icon: Icons.local_gas_station_outlined,
          tone: AppStatusColor.waiting,
          title: 'Cartão frota',
          subtitle: 'Mostra o cartão para o desconto no combustível',
          onPressed: onOpenFleetCard,
        ),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s20,
          AppSpacing.xs,
          AppSpacing.s20,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: AppSizes.sheetHandleWidth,
                height: AppSizes.sheetHandleHeight,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppStaggeredEntrance(
              index: 0,
              child: Text(
                'O que queres fazer?',
                style: textTheme.titleLarge
                    ?.copyWith(color: AppColors.textPrimary),
              ),
            ),
            for (var i = 0; i < actions.length; i++) ...[
              SizedBox(height: i == 0 ? AppSpacing.md : AppSpacing.sm),
              AppStaggeredEntrance(index: i + 1, child: actions[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  final IconData icon;
  final AppStatusColor tone;
  final String title;
  final String subtitle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
      side: const BorderSide(color: AppColors.divider),
    );
    return Material(
      color: AppColors.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Container(
                width: AppSizes.actionIconBox,
                height: AppSizes.actionIconBox,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.background,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
                child: Icon(icon, color: tone.foreground),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.xxs / 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
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
