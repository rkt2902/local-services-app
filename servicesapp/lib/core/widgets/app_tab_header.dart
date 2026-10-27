import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion_tokens.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// Uma tab do [AppTabs]. [count] mostra o contador ao lado ("Propostas 4");
/// 0 ou null não mostra nada.
class AppTabItem {
  const AppTabItem({required this.label, this.count});

  final String label;
  final int? count;
}

/// Tabs dos separadores (design A11): texto com sublinhado verde que desliza
/// entre tabs, 48 px de altura. As mesmas em Trabalhos, Pedidos do cliente e
/// Pedidos de ajuda.
class AppTabs extends StatelessWidget {
  const AppTabs({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<AppTabItem> items;
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

/// Cabeçalho dos separadores de topo (design A11, "Separador"): fundo
/// branco com linha por baixo, título grande, ações à direita (sino,
/// definições) e, por baixo, tabs ou outra fila ([bottom]). Igual em
/// Início, Pedidos, Trabalhos, Alertas e Perfil, nos dois papéis.
///
/// Não traz `SafeArea`: o ecrã que o usa já está dentro de uma.
class AppTabHeader extends StatelessWidget {
  const AppTabHeader({
    required this.title,
    this.overline,
    this.actions = const [],
    this.bottom,
    super.key,
  });

  final String title;

  /// Linha pequena por cima do título, no Início ("Bom dia").
  final String? overline;
  final List<Widget> actions;

  /// Tabs ([AppTabs]) ou outra fila de controlos por baixo do título.
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bottom = this.bottom;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.md,
              bottom == null ? AppSpacing.md : AppSpacing.xxs,
            ),
            child: ConstrainedBox(
              // Mesma altura com ou sem ações, para o título não saltar
              // entre separadores.
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (overline != null)
                          Text(
                            overline!,
                            style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.displaySmall?.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.xs),
                    actions[i],
                  ],
                ],
              ),
            ),
          ),
          ?bottom,
        ],
      ),
    );
  }
}

/// Cabeçalho de um ecrã à parte (design A11, "Ecrã à parte"): seta, título,
/// linha de contexto opcional e, por baixo, tabs ou ações ([bottom]).
/// Mesmo fundo branco e linha do [AppTabHeader].
class AppBackHeader extends StatelessWidget {
  const AppBackHeader({
    required this.title,
    required this.onBack,
    this.subtitle,
    this.bottom,
    super.key,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onBack;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final subtitle = this.subtitle;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.xs,
              AppSpacing.md,
              bottom == null ? AppSpacing.xs : 0,
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  tooltip: 'Voltar',
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleLarge
                              ?.copyWith(color: AppColors.textPrimary),
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ?bottom,
        ],
      ),
    );
  }
}
