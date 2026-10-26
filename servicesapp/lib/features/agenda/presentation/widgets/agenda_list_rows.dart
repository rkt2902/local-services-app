import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';

/// Linha tracejada com texto ao centro.
class _DashedRule extends StatelessWidget {
  const _DashedRule({required this.color});

  final Color color;

  static const double _dash = 5;
  static const double _gap = 4;
  static const double _thickness = 1.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / (_dash + _gap)).floor().clamp(
          0,
          200,
        );
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < count; i++)
              SizedBox(
                width: _dash,
                height: _thickness,
                child: ColoredBox(color: color),
              ),
          ],
        );
      },
    );
  }
}

/// Tempo livre entre duas entradas com hora (A6). Abaixo de 30 min passa ao
/// tom info ("Só 15 min até ao próximo"). Toque: adicionar trabalho com essa
/// hora já preenchida.
class AgendaFreeTimeRow extends StatelessWidget {
  const AgendaFreeTimeRow({
    required this.label,
    this.short = false,
    this.onTap,
    super.key,
  });

  /// "Livre das 11:30 às 14:00" ou "Só 15 min até ao próximo".
  final String label;
  final bool short;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final info = AppStatusColor.info;
    final Widget text = short
        ? Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s10,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: info.background,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: AppSizes.metaIcon,
                  color: info.foreground,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: info.foreground,
                    ),
                  ),
                ),
              ],
            ),
          )
        : Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          );
    final ruleColor = short
        ? AppColors.agendaInfoDash
        : AppColors.agendaExternalBorder;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(child: _DashedRule(color: ruleColor)),
            const SizedBox(width: AppSpacing.s10),
            Flexible(flex: 4, child: text),
            const SizedBox(width: AppSpacing.s10),
            Expanded(child: _DashedRule(color: ruleColor)),
          ],
        ),
      ),
    );
  }
}

/// Linha de "agora" (A6), só no Hoje. A integração atualiza [timeLabel] a
/// cada minuto e faz scroll até aqui ao abrir.
class AgendaNowLine extends StatelessWidget {
  const AgendaNowLine({required this.timeLabel, super.key});

  /// "11:42".
  final String timeLabel;

  static const double _dot = 8;
  static const double _line = 2;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Agora, $timeLabel',
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              timeLabel,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.surface,
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(-2, 0),
            child: Container(
              width: _dot,
              height: _dot,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const Expanded(
            child: SizedBox(
              height: _line,
              child: ColoredBox(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cabeçalho de dia das vistas Semana e Mês (A6). Fica fixo no topo ao
/// deslizar; toque abre esse dia na vista Hoje.
class AgendaDayHeader extends StatelessWidget {
  const AgendaDayHeader({
    required this.dayLabel,
    this.isToday = false,
    this.countLabel,
    this.hasOverlap = false,
    this.blockLabel,
    this.showDivider = true,
    this.onTap,
    super.key,
  });

  /// "Terça, 28 out".
  final String dayLabel;
  final bool isToday;

  /// "3 trabalhos"; nulo = "Livre".
  final String? countLabel;
  final bool hasOverlap;

  /// "Folga": dia indisponível (nome a cinzento).
  final String? blockLabel;
  final bool showDivider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
    );

    Widget trailing;
    if (blockLabel != null) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.event_busy_outlined,
            size: AppSizes.metaIcon,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(blockLabel!, style: secondary),
        ],
      );
    } else if (countLabel == null) {
      trailing = Text(
        'Livre',
        style: secondary?.copyWith(color: AppColors.textMuted),
      );
    } else {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasOverlap) ...[
            Icon(
              Icons.warning_rounded,
              size: AppSizes.inlineIcon,
              color: AppStatusColor.waiting.foreground,
              semanticLabel: 'Trabalhos que coincidem',
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(countLabel!, style: secondary),
        ],
      );
    }

    return Material(
      color: AppColors.background,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            border: showDivider
                ? const Border(bottom: BorderSide(color: AppColors.divider))
                : null,
          ),
          child: Row(
            children: [
              if (isToday) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'HOJE',
                    style: textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.surface,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Text(
                  dayLabel,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: blockLabel != null
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
