import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_motion.dart';

/// Folha do "+" do jardineiro (design U2, reordenada no A10 M4): primeiro
/// a Agenda, que é o que mais se repete no dia a dia ("Adicionar à agenda"
/// em destaque, "Marcar indisponível" mais discreto), um divisor e depois
/// Procurar trabalho, Pedidos de ajuda e o Cartão frota, este só quando o
/// cartão está ativo ([showFleetCard]). Não navega: cada callback fecha e
/// decide o destino.
///
/// Sem [AppSheet] de propósito: aqui não há ação principal nem botão de
/// fechar (o "+" da barra vira "✕" enquanto a folha está aberta).
class WorkerQuickActionsSheet extends StatelessWidget {
  const WorkerQuickActionsSheet({
    super.key,
    required this.onFindWork,
    required this.onOpenHelpRequests,
    required this.onOpenFleetCard,
    this.onAddToAgenda,
    this.onMarkUnavailable,
    this.showFleetCard = false,
  });

  final VoidCallback onFindWork;

  /// "Adicionar à agenda": o formulário com "Trabalho" e a data de hoje.
  final VoidCallback? onAddToAgenda;

  /// "Marcar indisponível": o mesmo formulário com "Indisponível".
  final VoidCallback? onMarkUnavailable;
  final VoidCallback onOpenHelpRequests;
  final VoidCallback onOpenFleetCard;
  final bool showFleetCard;

  @override
  Widget build(BuildContext context) {
    final agenda = [
      if (onAddToAgenda != null)
        _QuickActionCard(
          icon: Icons.edit_calendar_outlined,
          title: 'Adicionar à agenda',
          subtitle: 'Um trabalho fora da app',
          emphasis: true,
          onPressed: onAddToAgenda!,
        ),
      if (onMarkUnavailable != null)
        _QuickActionCard(
          icon: Icons.event_busy_outlined,
          title: 'Marcar indisponível',
          onPressed: onMarkUnavailable!,
        ),
    ];
    final others = [
      _QuickActionCard(
        icon: Icons.search_rounded,
        title: 'Procurar trabalho',
        onPressed: onFindWork,
      ),
      _QuickActionCard(
        icon: Icons.group_outlined,
        title: 'Pedidos de ajuda',
        onPressed: onOpenHelpRequests,
      ),
      if (showFleetCard)
        _QuickActionCard(
          icon: Icons.local_gas_station_outlined,
          title: 'Cartão frota',
          onPressed: onOpenFleetCard,
        ),
    ];

    var index = 0;
    Widget staggered(Widget child) =>
        AppStaggeredEntrance(index: index++, child: child);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.md,
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
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < agenda.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.xxs),
              staggered(agenda[i]),
            ],
            if (agenda.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Divider(height: 1, color: AppColors.divider),
              ),
            for (final action in others) staggered(action),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.onPressed,
    this.subtitle,
    this.emphasis = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Só "Adicionar à agenda": fundo verde claro e ícone cheio.
  final bool emphasis;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const neutral = AppStatusColor.neutral;
    final radius = BorderRadius.circular(AppRadius.card);
    return Material(
      color: emphasis ? AppColors.primaryContainer : AppColors.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: emphasis ? AppSpacing.sm : AppSpacing.xs,
          ),
          child: Row(
            children: [
              Container(
                width: AppSizes.actionIconBox,
                height: emphasis ? AppSizes.actionIconBox : AppSizes.rowIconBox,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: emphasis ? AppColors.primary : neutral.background,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
                child: Icon(
                  icon,
                  color: emphasis ? AppColors.surface : neutral.foreground,
                ),
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
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xxs / 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
