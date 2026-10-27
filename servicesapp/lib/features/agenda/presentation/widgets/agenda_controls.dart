import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';

/// Tab do ecrã Trabalhos (A8): texto grande com sublinhado verde de largura
/// toda. [count] mostra o contador ao lado ("Propostas 4").
class AgendaTabItem {
  const AgendaTabItem({required this.label, this.count});

  final String label;
  final int? count;
}

/// Tabs Agenda · Propostas · Histórico. O sublinhado desliza entre tabs.
class AgendaTabs extends StatelessWidget {
  const AgendaTabs({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<AgendaTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const double _height = 48;
  static const double _indicator = 3;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tabWidth = constraints.maxWidth / items.length;
        return SizedBox(
          height: _height,
          child: Stack(
            children: [
              Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == selectedIndex,
                        child: InkWell(
                          onTap: () => onSelected(i),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    items[i].label,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.titleMedium?.copyWith(
                                      fontWeight: i == selectedIndex
                                          ? FontWeight.w800
                                          : FontWeight.w700,
                                      color: i == selectedIndex
                                          ? AppColors.primary
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                if ((items[i].count ?? 0) > 0) ...[
                                  const SizedBox(width: AppSpacing.s6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.s6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.agendaNeutralSurface,
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.pill,
                                      ),
                                    ),
                                    child: Text(
                                      '${items[i].count}',
                                      style: textTheme.labelMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textStrong,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              AnimatedPositioned(
                duration: reduceMotion ? Duration.zero : AppMotionDuration.fast,
                curve: AppMotionCurve.standard,
                left: tabWidth * selectedIndex,
                width: tabWidth,
                bottom: 0,
                height: _indicator,
                child: const ColoredBox(color: AppColors.primary),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Vista da Agenda.
enum AgendaRange {
  day('Hoje'),
  week('Semana'),
  month('Mês');

  const AgendaRange(this.label);

  final String label;
}

/// Seletor Hoje · Semana · Mês (A8): cápsula cinzenta pequena com o ativo em
/// branco, mais leve que as tabs para não parecerem dois menus iguais.
class AgendaRangeSelector extends StatelessWidget {
  const AgendaRangeSelector({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final AgendaRange selected;
  final ValueChanged<AgendaRange> onSelected;

  static const double _height = 40;
  static const double _inset = 3;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      height: _height,
      padding: const EdgeInsets.all(_inset),
      decoration: BoxDecoration(
        color: AppColors.divider,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          for (final range in AgendaRange.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: range == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelected(range),
                  child: AnimatedContainer(
                    duration: AppMotionDuration.fast,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: range == selected
                          ? AppColors.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: range == selected
                          ? [
                              BoxShadow(
                                color: AppColors.textPrimary.withValues(
                                  alpha: 0.08,
                                ),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      range.label,
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: range == selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: range == selected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Botão "Hoje": volta ao dia atual; atenuado quando já lá está.
class AgendaTodayButton extends StatelessWidget {
  const AgendaTodayButton({required this.onPressed, super.key});

  /// Nulo = já está em hoje (atenuado).
  final VoidCallback? onPressed;

  static const double _height = 40;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = enabled ? AppColors.primary : AppColors.agendaDashed;
    final shape = StadiumBorder(
      side: BorderSide(
        color: enabled ? AppColors.agendaAppBorder : AppColors.divider,
        width: 1.5,
      ),
    );
    return SizedBox(
      height: _height,
      child: Material(
        color: enabled ? AppColors.surface : AppColors.background,
        shape: shape,
        child: InkWell(
          onTap: onPressed,
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.today_outlined,
                  size: AppSizes.inlineIcon,
                  color: fg,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  'Hoje',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: fg,
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

/// Setas e período ("Segunda, 27 out", "27 out a 2 nov", "Outubro 2026").
/// Toque no texto abre o calendário para saltar para uma data.
class AgendaPeriodNav extends StatelessWidget {
  const AgendaPeriodNav({
    required this.label,
    required this.onPrevious,
    required this.onNext,
    this.onLabelTap,
    super.key,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onLabelTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPrevious,
          tooltip: 'Anterior',
          icon: const Icon(
            Icons.chevron_left_rounded,
            color: AppColors.textSecondary,
          ),
        ),
        Flexible(
          child: InkWell(
            onTap: onLabelTap,
            borderRadius: BorderRadius.circular(AppRadius.input),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  // Toque abre o calendário: a seta diz que há mais.
                  if (onLabelTap != null) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    const Icon(
                      Icons.expand_more_rounded,
                      size: AppSizes.emphasisIcon,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          tooltip: 'Seguinte',
          icon: const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// "Mostrar propostas": liga e desliga os cartões tracejados. Toda a linha
/// é tocável (44 px).
class AgendaProposalsToggle extends StatelessWidget {
  const AgendaProposalsToggle({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSizes.headerIconButton,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Em ecrãs estreitos parte em duas linhas, como no design.
              Flexible(
                child: Text(
                  'Mostrar propostas',
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textStrong,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: AppColors.agendaExternalBorder,
                thumbColor: const WidgetStatePropertyAll(AppColors.surface),
                trackOutlineColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
