import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import 'agenda_decorations.dart';
import 'agenda_entry_card.dart';

/// Amostra de um tipo de entrada, igual ao início do cartão (A7).
class _KindSwatch extends StatelessWidget {
  const _KindSwatch({required this.kind});

  final AgendaCardKind kind;

  static const double _width = 44;
  static const double _height = 30;
  static const double _radius = 8;
  static const double _bar = 6;

  @override
  Widget build(BuildContext context) {
    const size = Size(_width, _height);
    switch (kind) {
      case AgendaCardKind.proposal:
        return SizedBox.fromSize(
          size: size,
          child: const AgendaDashedBorder(radius: _radius, child: SizedBox()),
        );
      case AgendaCardKind.block:
        return SizedBox.fromSize(
          size: size,
          child: const AgendaStripes(
            radius: _radius,
            stripeWidth: 6,
            child: SizedBox(),
          ),
        );
      default:
        final (
          Color bg,
          Color border,
          Color bar,
          double width,
        ) = switch (kind) {
          AgendaCardKind.app => (
            AppColors.surface,
            AppColors.agendaAppBorder,
            AppColors.primary,
            1.0,
          ),
          AgendaCardKind.helper => (
            AppColors.agendaHelperSurface,
            AppColors.agendaHelperBorder,
            AppColors.agendaHelperBar,
            1.0,
          ),
          _ => (
            AppColors.surface,
            AppColors.agendaExternalBorder,
            AppColors.agendaExternalBorder,
            1.5,
          ),
        };
        return Container(
          width: _width,
          height: _height,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(color: border, width: width),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: _bar,
                height: double.infinity,
                child: ColoredBox(color: bar),
              ),
            ),
          ),
        );
    }
  }
}

/// Conteúdo da folha "O que significam as cores" (A7). Abre pelo ícone de
/// ajuda no topo da Agenda, dentro de `AppSheet`.
class AgendaLegendSheet extends StatelessWidget {
  const AgendaLegendSheet({super.key, this.showTitle = true});

  /// Falso dentro de `AppSheet`, que já tem o título.
  final bool showTitle;

  static const _rows = [
    (AgendaCardKind.app, 'Trabalho da app', 'És tu o responsável'),
    (AgendaCardKind.helper, 'Ajudante', 'Ajudas outro jardineiro'),
    (AgendaCardKind.external, 'Fora da app', 'Trabalho que tu adicionaste'),
    (AgendaCardKind.proposal, 'Proposta enviada', 'À espera do cliente'),
    (AgendaCardKind.block, 'Indisponível', 'Férias, folga, consulta'),
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    Widget row(Widget swatch, String title, String subtitle) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s10),
      child: Row(
        children: [
          swatch,
          const SizedBox(width: AppSpacing.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle) ...[
          Text(
            'O que significam as cores?',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        for (final (kind, title, subtitle) in _rows)
          row(_KindSwatch(kind: kind), title, subtitle),
        const Divider(height: AppSpacing.sm, color: AppColors.divider),
        row(
          SizedBox(
            width: _KindSwatch._width,
            child: Icon(
              Icons.warning_rounded,
              size: AppSizes.rowIcon,
              color: AppStatusColor.waiting.foreground,
            ),
          ),
          'Coincidem',
          'Dois trabalhos à mesma hora',
        ),
      ],
    );
  }
}

/// Legenda em linha, para o topo do Mês (A7).
class AgendaLegendInline extends StatelessWidget {
  const AgendaLegendInline({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    );

    Widget item(Widget dot, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: AppSpacing.s6),
        Text(label, style: style),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.divider),
      ),
      child: Wrap(
        spacing: AppSpacing.s14,
        runSpacing: AppSpacing.xs,
        children: [
          item(const AgendaKindDot(kind: AgendaCardKind.app), 'App'),
          item(const AgendaKindDot(kind: AgendaCardKind.helper), 'Ajudante'),
          item(
            const AgendaKindDot(kind: AgendaCardKind.external),
            'Fora da app',
          ),
          item(const AgendaKindDot(kind: AgendaCardKind.proposal), 'Proposta'),
          item(const AgendaKindDot(kind: AgendaCardKind.block), 'Indisponível'),
        ],
      ),
    );
  }
}

/// Ponto de cor por tipo, usado na grelha do Mês, na faixa da Semana e na
/// legenda em linha.
class AgendaKindDot extends StatelessWidget {
  const AgendaKindDot({required this.kind, this.size = 10, super.key});

  final AgendaCardKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case AgendaCardKind.app:
      case AgendaCardKind.helper:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: kind == AgendaCardKind.app
                ? AppColors.primary
                : AppColors.agendaHelperBar,
            shape: BoxShape.circle,
          ),
        );
      case AgendaCardKind.external:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.agendaDashed, width: 2),
          ),
        );
      case AgendaCardKind.proposal:
        return SizedBox(
          width: size,
          height: size,
          child: AgendaDashedBorder(
            radius: size / 2,
            color: AppColors.textSecondary,
            strokeWidth: 1.5,
            child: const SizedBox.expand(),
          ),
        );
      case AgendaCardKind.block:
        return SizedBox(
          width: size,
          height: size,
          child: const AgendaStripes(
            radius: 2,
            stripeWidth: 2,
            background: AppColors.agendaNeutralSurface,
            stripe: AppColors.agendaExternalBorder,
            child: SizedBox.expand(),
          ),
        );
    }
  }
}
