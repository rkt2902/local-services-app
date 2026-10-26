import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import 'agenda_decorations.dart';

/// Os 5 aspetos de uma entrada da agenda (folha de componentes, A1). Cada um
/// distingue-se sem ler: barra e quadrado do ícone (cheio, claro, cinzento),
/// fundo (branco, verde claro, riscas) e contorno (fino, tracejado).
enum AgendaCardKind { app, helper, external, proposal, block }

/// Etiqueta de estado/tipo do cartão completo.
enum AgendaCardPill {
  scheduled('Marcado'),
  inProgress('Em curso'),
  awaitingConfirmation('Por confirmar'),
  done('Concluído'),
  helper('Ajudante'),
  external('Fora da app'),
  proposal('À espera do cliente'),
  block('Indisponível');

  const AgendaCardPill(this.label);

  final String label;

  /// Nas linhas compactas da Semana, onde o espaço é curto.
  String get shortLabel => this == AgendaCardPill.proposal ? 'À espera' : label;
}

/// Ícone à direita da linha compacta (A2): no máximo um por linha.
enum AgendaCompactMarker {
  none,
  helper,
  external,
  proposal,
  repeats,
  changed,
  done,
  block,
}

/// Botão de ação rápida do cartão completo (44 px de altura).
class AgendaCardAction {
  const AgendaCardAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  /// Verde cheio (Iniciar, Terminar); os outros são contornados.
  final bool primary;
}

/// Dados já formatados de uma entrada. A integração monta isto a partir de
/// `AgendaEntry`; o cartão não calcula nada.
class AgendaEntryCardData {
  const AgendaEntryCardData({
    required this.kind,
    required this.title,
    required this.serviceIcon,
    this.startLabel,
    this.endLabel,
    this.dayIndex,
    this.dayCount,
    this.timeToArrange = false,
    this.subtitle,
    this.amountLabel,
    this.pill,
    this.detailLabel,
    this.repeats = false,
    this.changedLabel,
    this.done = false,
    this.current = false,
    this.highlighted = false,
    this.actions = const [],
    this.onTap,
  });

  final AgendaCardKind kind;

  /// "Corte de relva", "Folga".
  final String title;
  final IconData serviceIcon;

  /// "09:00". Nulo com [timeToArrange] ou num dia todo.
  final String? startLabel;

  /// "11:00", fim estimado.
  final String? endLabel;

  /// Vários dias: "Dia 2 de 3" com a barra de progresso.
  final int? dayIndex;
  final int? dayCount;

  /// "Hora a combinar" (trabalho com data e sem hora).
  final bool timeToArrange;

  /// "Cascais · Maria Santos", "Sintra · com Rui Ferreira".
  final String? subtitle;

  /// "≈ 60 €", "120 €".
  final String? amountLabel;

  final AgendaCardPill? pill;

  /// Texto ao lado da etiqueta: "Todas as terças", "27 a 29 out · 08:00 a
  /// 17:00".
  final String? detailLabel;

  /// Série que se repete: ícone ao lado do título.
  final bool repeats;

  /// "Mudado só este dia · era às 08:00".
  final String? changedLabel;

  /// Concluído ou feito: atenuado, sem botões, visto no lugar do ícone.
  final bool done;

  /// A hora atual cai dentro desta entrada (vista Hoje): contorno verde de
  /// 2 px.
  final bool current;

  /// Acabado de guardar no formulário (F8B): contorno verde e um halo.
  final bool highlighted;

  final List<AgendaCardAction> actions;
  final VoidCallback? onTap;

  bool get isMultiDay => (dayCount ?? 1) > 1 && dayIndex != null;
  bool get isAllDay => startLabel == null && !timeToArrange && !isMultiDay;
}

class _KindStyle {
  const _KindStyle({
    required this.background,
    required this.border,
    required this.borderWidth,
    required this.bar,
    required this.iconBoxColor,
    required this.iconColor,
    this.iconBoxBorder,
    this.shadow = false,
  });

  final Color background;
  final Color border;
  final double borderWidth;
  final Color? bar;
  final Color? iconBoxColor;
  final Color iconColor;
  final Color? iconBoxBorder;
  final bool shadow;

  static _KindStyle of(AgendaCardKind kind) {
    switch (kind) {
      case AgendaCardKind.app:
        return const _KindStyle(
          background: AppColors.surface,
          border: AppColors.agendaAppBorder,
          borderWidth: 1,
          bar: AppColors.primary,
          iconBoxColor: AppColors.primary,
          iconColor: AppColors.surface,
          shadow: true,
        );
      case AgendaCardKind.helper:
        return const _KindStyle(
          background: AppColors.agendaHelperSurface,
          border: AppColors.agendaHelperBorder,
          borderWidth: 1,
          bar: AppColors.agendaHelperBar,
          iconBoxColor: AppColors.surface,
          iconBoxBorder: AppColors.agendaAppBorder,
          iconColor: AppColors.accent,
        );
      case AgendaCardKind.external:
        return const _KindStyle(
          background: AppColors.surface,
          border: AppColors.agendaExternalBorder,
          borderWidth: 1.5,
          bar: AppColors.agendaExternalBorder,
          iconBoxColor: AppColors.agendaNeutralSurface,
          iconColor: AppColors.textSecondary,
        );
      case AgendaCardKind.proposal:
        return const _KindStyle(
          background: Colors.transparent,
          border: AppColors.textMuted,
          borderWidth: 1.5,
          bar: null,
          iconBoxColor: null,
          iconColor: AppColors.textSecondary,
        );
      case AgendaCardKind.block:
        return const _KindStyle(
          background: Colors.transparent,
          border: Colors.transparent,
          borderWidth: 0,
          bar: null,
          iconBoxColor: AppColors.surface,
          iconColor: AppColors.textSecondary,
        );
    }
  }
}

const double _barWidth = 6;
const double _timeColumnWidth = 50;
const double _compactTimeWidth = 44;
const double _compactHeight = 52;
const double _doneOpacity = 0.62;
const double _currentBorderWidth = 2;

/// Moldura comum: barra à esquerda, fundo, contorno (fino, tracejado ou
/// riscas) e toque.
class _AgendaFrame extends StatelessWidget {
  const _AgendaFrame({
    required this.kind,
    required this.radius,
    required this.padding,
    required this.child,
    this.done = false,
    this.current = false,
    this.onTap,
  });

  final AgendaCardKind kind;
  final double radius;
  final EdgeInsets padding;
  final Widget child;
  final bool done;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = _KindStyle.of(kind);
    final borderRadius = BorderRadius.circular(radius);

    Widget content = Padding(padding: padding, child: child);
    if (style.bar != null) {
      // passthrough: a linha compacta herda os 52 px e centra o conteúdo.
      content = Stack(
        fit: StackFit.passthrough,
        children: [
          content,
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _barWidth,
            child: ColoredBox(color: style.bar!),
          ),
        ],
      );
    }

    content = Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, borderRadius: borderRadius, child: content),
    );

    Widget framed;
    switch (kind) {
      case AgendaCardKind.proposal:
        framed = AgendaDashedBorder(radius: radius, child: content);
      case AgendaCardKind.block:
        framed = AgendaStripes(radius: radius, child: content);
      default:
        framed = DecoratedBox(
          decoration: BoxDecoration(
            color: style.background,
            borderRadius: borderRadius,
            border: Border.all(
              color: done
                  ? AppColors.divider
                  : current
                  ? AppColors.primary
                  : style.border,
              width: current && !done ? _currentBorderWidth : style.borderWidth,
            ),
            boxShadow: style.shadow && !done
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(borderRadius: borderRadius, child: content),
        );
    }

    return done ? Opacity(opacity: _doneOpacity, child: framed) : framed;
  }
}

/// Cartão completo da vista Hoje (A1 e A3).
class AgendaEntryCard extends StatelessWidget {
  const AgendaEntryCard({required this.data, super.key});

  final AgendaEntryCardData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = _KindStyle.of(data.kind);
    final tentative = data.kind == AgendaCardKind.proposal;
    final muted = tentative || data.kind == AgendaCardKind.block;
    final showActions = !data.done && data.actions.isNotEmpty;

    return Semantics(
      button: data.onTap != null,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppMotionDuration.fast,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: [
            BoxShadow(
              color: data.highlighted
                  ? AppColors.primaryContainer
                  : AppColors.primaryContainer.withValues(alpha: 0),
              spreadRadius: AppSpacing.s6,
            ),
          ],
        ),
        child: _card(context, textTheme, style, tentative, muted, showActions),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    TextTheme textTheme,
    _KindStyle style,
    bool tentative,
    bool muted,
    bool showActions,
  ) {
    return _AgendaFrame(
      kind: data.kind,
      radius: AppRadius.card,
      done: data.done,
      current: data.current || data.highlighted,
      onTap: data.onTap,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.s14,
        AppSpacing.s14,
        AppSpacing.s14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _timeColumnWidth,
                child: _TimeColumn(data: data, muted: tentative),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _IconBox(
                          icon: data.done
                              ? Icons.check_circle_rounded
                              : data.serviceIcon,
                          style: style,
                          done: data.done,
                          dashed: tentative,
                        ),
                        const SizedBox(width: AppSpacing.s10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      data.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: muted
                                            ? AppColors.textStrong
                                            : AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (data.repeats) ...[
                                    const SizedBox(width: AppSpacing.xxs),
                                    const Icon(
                                      Icons.repeat_rounded,
                                      size: AppSizes.inlineIcon,
                                      color: AppColors.textSecondary,
                                    ),
                                  ],
                                ],
                              ),
                              if (data.subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  data.subtitle!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (data.amountLabel != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            data.amountLabel!,
                            style: textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (data.pill != null || data.detailLabel != null) ...[
                      const SizedBox(height: AppSpacing.s10),
                      Wrap(
                        spacing: AppSpacing.s6,
                        runSpacing: AppSpacing.s6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (data.pill != null)
                            AgendaPillBadge(pill: data.pill!),
                          if (data.detailLabel != null)
                            Text(
                              data.detailLabel!,
                              style: textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (data.changedLabel != null) ...[
                      const SizedBox(height: AppSpacing.s10),
                      _ChangedNote(label: data.changedLabel!),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (showActions) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (var i = 0; i < data.actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.s6),
                  Expanded(child: _ActionButton(action: data.actions[i])),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TimeColumn extends StatelessWidget {
  const _TimeColumn({required this.data, required this.muted});

  final AgendaEntryCardData data;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final strong = textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
      color: muted ? AppColors.textSecondary : AppColors.textPrimary,
    );
    final secondary = textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: muted ? AppColors.textMuted : AppColors.textSecondary,
    );

    if (data.isMultiDay) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dia ${data.dayIndex}',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          Text('de ${data.dayCount}', style: secondary),
          const SizedBox(height: AppSpacing.s6),
          AgendaDayProgress(index: data.dayIndex!, count: data.dayCount!),
        ],
      );
    }
    if (data.timeToArrange) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.schedule_rounded,
            size: AppSizes.rowIcon,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.xxs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Hora a\ncombinar',
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      );
    }
    if (data.isAllDay) {
      return Text(
        'Dia todo',
        style: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          height: 1.2,
          color: AppColors.textStrong,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(data.startLabel!, style: strong),
        if (data.endLabel != null) ...[
          const SizedBox(height: 2),
          Text(data.endLabel!, style: secondary),
        ],
      ],
    );
  }
}

/// Barra de progresso de um trabalho de vários dias ("Dia 2 de 3").
class AgendaDayProgress extends StatelessWidget {
  const AgendaDayProgress({
    required this.index,
    required this.count,
    super.key,
  });

  final int index;
  final int count;

  static const double _segmentWidth = 12;
  static const double _segmentHeight = 5;
  static const int _maxSegments = 7;

  @override
  Widget build(BuildContext context) {
    final shown = count > _maxSegments ? _maxSegments : count;
    final filled = (index * shown / count).ceil();
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (var i = 0; i < shown; i++)
          Container(
            width: _segmentWidth,
            height: _segmentHeight,
            decoration: BoxDecoration(
              color: i < filled ? AppColors.primary : AppColors.divider,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
      ],
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({
    required this.icon,
    required this.style,
    required this.done,
    required this.dashed,
  });

  final IconData icon;
  final _KindStyle style;
  final bool done;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.primaryContainer : style.iconBoxColor;
    final iconColor = done ? AppColors.primary : style.iconColor;
    final box = Container(
      width: AppSizes.rowIconBox,
      height: AppSizes.rowIconBox,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: style.iconBoxBorder == null || done
            ? null
            : Border.all(color: style.iconBoxBorder!),
      ),
      child: Icon(icon, size: AppSizes.rowIcon, color: iconColor),
    );
    if (!dashed) return box;
    return AgendaDashedBorder(
      radius: AppRadius.input,
      color: AppColors.agendaDashed,
      child: box,
    );
  }
}

class _ChangedNote extends StatelessWidget {
  const _ChangedNote({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tone = AppStatusColor.info;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s10,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppSpacing.s10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.edit_calendar_outlined,
            size: AppSizes.metaIcon,
            color: tone.foreground,
          ),
          const SizedBox(width: AppSpacing.s6),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: tone.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action});

  final AgendaCardAction action;

  static const double _height = 44;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final primary = action.primary;
    final foreground = primary ? AppColors.surface : AppColors.primary;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.input),
      side: primary
          ? BorderSide.none
          : const BorderSide(color: AppColors.agendaAppBorder, width: 1.5),
    );

    return SizedBox(
      height: _height,
      child: Material(
        color: primary ? AppColors.primary : AppColors.surface,
        shape: shape,
        child: InkWell(
          onTap: action.onPressed,
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  action.icon,
                  size: primary ? AppSizes.emphasisIcon : AppSizes.inlineIcon,
                  color: foreground,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Flexible(
                  child: Text(
                    action.label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: foreground,
                      height: 1.1,
                    ),
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

/// Etiqueta do cartão (estados da pill, A1).
class AgendaPillBadge extends StatelessWidget {
  const AgendaPillBadge({required this.pill, this.dense = false, super.key});

  final AgendaCardPill pill;

  /// Versão pequena das linhas da Semana, com o texto curto.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (
      Color bg,
      Color fg,
      IconData? icon,
      bool dot,
      Color? border,
    ) = switch (pill) {
      AgendaCardPill.scheduled => (
        AppColors.primaryContainer,
        AppColors.primary,
        null,
        false,
        null,
      ),
      AgendaCardPill.inProgress => (
        AppStatusColor.info.background,
        AppStatusColor.info.foreground,
        null,
        true,
        null,
      ),
      AgendaCardPill.awaitingConfirmation => (
        AppStatusColor.waiting.background,
        AppStatusColor.waiting.foreground,
        null,
        false,
        null,
      ),
      AgendaCardPill.done => (
        AppColors.primaryContainer,
        AppColors.primary,
        Icons.check_rounded,
        false,
        null,
      ),
      AgendaCardPill.helper => (
        AppColors.surface,
        AppColors.primary,
        Icons.group_outlined,
        false,
        AppColors.agendaAppBorder,
      ),
      AgendaCardPill.external => (
        AppColors.agendaNeutralSurface,
        AppColors.textStrong,
        Icons.edit_note_rounded,
        false,
        null,
      ),
      AgendaCardPill.proposal => (
        AppStatusColor.waiting.background,
        AppStatusColor.waiting.foreground,
        Icons.hourglass_top_rounded,
        false,
        null,
      ),
      AgendaCardPill.block => (
        AppColors.surface,
        AppColors.textStrong,
        Icons.block_rounded,
        false,
        null,
      ),
    };

    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.xs : AppSpacing.s10,
        vertical: dense ? 3 : AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: AppSizes.statusDot,
              height: AppSizes.statusDot,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.xxs),
          ],
          if (icon != null) ...[
            Icon(icon, size: AppSizes.metaIcon, color: fg),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Text(
            dense ? pill.shortLabel : pill.label,
            style: (dense ? textTheme.labelMedium : textTheme.bodySmall)
                ?.copyWith(fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}

/// Linha compacta de 52 px das vistas Semana e Mês (A2): barra de cor,
/// hora, serviço e zona. A zona é a primeira a desaparecer.
class AgendaEntryCompactRow extends StatelessWidget {
  const AgendaEntryCompactRow({
    required this.kind,
    required this.title,
    this.startLabel,
    this.dayIndex,
    this.dayCount,
    this.timeToArrange = false,
    this.zone,
    this.marker = AgendaCompactMarker.none,
    this.done = false,
    this.onTap,
    super.key,
  });

  final AgendaCardKind kind;
  final String title;
  final String? startLabel;
  final int? dayIndex;
  final int? dayCount;
  final bool timeToArrange;
  final String? zone;
  final AgendaCompactMarker marker;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasBar = _KindStyle.of(kind).bar != null;
    final tentative = kind == AgendaCardKind.proposal;
    final muted = tentative || kind == AgendaCardKind.block;
    final multiDay = (dayCount ?? 1) > 1 && dayIndex != null;

    final small = textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.1,
      color: AppColors.textStrong,
    );
    Widget time;
    if (multiDay) {
      time = Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'Dia $dayIndex\n'),
            TextSpan(
              text: 'de $dayCount',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        style: small?.copyWith(color: AppColors.textPrimary),
      );
    } else if (timeToArrange) {
      time = Text(
        'Hora a\ncombinar',
        style: small?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      );
    } else if (startLabel == null) {
      time = Text('Dia\ntodo', style: small);
    } else {
      time = Text(
        startLabel!,
        style: textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: tentative ? AppColors.textSecondary : AppColors.textPrimary,
          decoration: done ? TextDecoration.lineThrough : null,
          decorationColor: AppColors.agendaDashed,
        ),
      );
    }

    return Semantics(
      button: onTap != null,
      child: SizedBox(
        height: _compactHeight,
        child: _AgendaFrame(
          kind: kind,
          radius: AppRadius.input,
          done: done,
          onTap: onTap,
          padding: EdgeInsets.only(
            left: hasBar ? _barWidth + AppSpacing.s10 : AppSpacing.sm,
            right: AppSpacing.sm,
          ),
          child: Row(
            children: [
              SizedBox(
                width: _compactTimeWidth,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: time,
                ),
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (zone != null)
                        TextSpan(
                          text: ' · $zone',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: muted ? AppColors.textStrong : AppColors.textPrimary,
                  ),
                ),
              ),
              if (_markerFor(context) case final Widget m) ...[
                const SizedBox(width: AppSpacing.xs),
                m,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget? _markerFor(BuildContext context) {
    const size = AppSizes.inlineIcon;
    switch (marker) {
      case AgendaCompactMarker.none:
        return null;
      case AgendaCompactMarker.helper:
        return const Icon(
          Icons.group_outlined,
          size: size,
          color: AppColors.accent,
          semanticLabel: 'Ajudante',
        );
      case AgendaCompactMarker.external:
        return Text(
          'Fora',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        );
      case AgendaCompactMarker.proposal:
        return Icon(
          Icons.hourglass_top_rounded,
          size: size,
          color: AppStatusColor.waiting.foreground,
          semanticLabel: 'À espera do cliente',
        );
      case AgendaCompactMarker.repeats:
        return const Icon(
          Icons.repeat_rounded,
          size: size,
          color: AppColors.textSecondary,
          semanticLabel: 'Repete',
        );
      case AgendaCompactMarker.changed:
        return Icon(
          Icons.edit_calendar_outlined,
          size: size,
          color: AppStatusColor.info.foreground,
          semanticLabel: 'Mudado só este dia',
        );
      case AgendaCompactMarker.done:
        return const Icon(
          Icons.check_circle_rounded,
          size: AppSizes.emphasisIcon,
          color: AppColors.primary,
          semanticLabel: 'Concluído',
        );
      case AgendaCompactMarker.block:
        return const Icon(
          Icons.event_busy_outlined,
          size: size,
          color: AppColors.textSecondary,
          semanticLabel: 'Indisponível',
        );
    }
  }
}

/// Linha da lista da Semana (S1): hora de início e de fim, serviço (com o
/// ícone de repetir), zona e pessoa, e uma só etiqueta à direita. Mesmas
/// cores e contornos que o cartão completo, em mais baixo.
class AgendaWeekEntryRow extends StatelessWidget {
  const AgendaWeekEntryRow({
    required this.kind,
    required this.title,
    this.startLabel,
    this.endLabel,
    this.subtitle,
    this.repeats = false,
    this.timeToArrange = false,
    this.dayIndex,
    this.dayCount,
    this.pill,
    this.done = false,
    this.onTap,
    super.key,
  });

  final AgendaCardKind kind;
  final String title;
  final String? startLabel;
  final String? endLabel;

  /// "Cascais · Maria Santos".
  final String? subtitle;
  final bool repeats;
  final bool timeToArrange;

  /// Trabalho de vários dias: etiqueta "Dia 1 de 3".
  final int? dayIndex;
  final int? dayCount;

  /// "Marcado" não aparece: é o normal.
  final AgendaCardPill? pill;
  final bool done;
  final VoidCallback? onTap;

  static const double _minHeight = 58;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasBar = _KindStyle.of(kind).bar != null;
    final tentative = kind == AgendaCardKind.proposal;
    final multiDay = (dayCount ?? 1) > 1 && dayIndex != null;

    final strong = textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: tentative ? AppColors.textSecondary : AppColors.textPrimary,
    );
    final small = textTheme.labelMedium?.copyWith(
      color: AppColors.textSecondary,
    );
    final (String top, String? bottom) = startLabel != null
        ? (startLabel!, endLabel)
        : timeToArrange
        ? ('Hora a', 'combinar')
        : ('Dia', 'todo');

    Widget? badge;
    if (done) {
      badge = const AgendaPillBadge(pill: AgendaCardPill.done, dense: true);
    } else if (multiDay) {
      badge = _DayBadge(label: 'Dia $dayIndex de $dayCount');
    } else if (pill != null && pill != AgendaCardPill.scheduled) {
      badge = AgendaPillBadge(pill: pill!, dense: true);
    }

    return Semantics(
      button: onTap != null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _minHeight),
        child: _AgendaFrame(
          kind: kind,
          radius: AppRadius.input,
          done: done,
          onTap: onTap,
          padding: EdgeInsets.fromLTRB(
            hasBar ? _barWidth + AppSpacing.sm : AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.s10,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              SizedBox(
                width: _compactTimeWidth,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(top, style: strong),
                      if (bottom != null) Text(bottom, style: small),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: tentative
                                  ? AppColors.textStrong
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (repeats) ...[
                          const SizedBox(width: AppSpacing.xxs),
                          const Icon(
                            Icons.repeat_rounded,
                            size: AppSizes.metaIcon,
                            color: AppColors.textSecondary,
                            semanticLabel: 'Repete',
                          ),
                        ],
                      ],
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: small,
                      ),
                  ],
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: AppSpacing.xs),
                badge,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Dia 2 de 3" das linhas da Semana.
class _DayBadge extends StatelessWidget {
  const _DayBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.date_range_outlined,
            size: AppSizes.metaIcon,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
