import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion_tokens.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_color.dart';
import 'app_motion.dart';

enum StatusTimelineStepState { completed, current, future }

class StatusTimelineStepData {
  const StatusTimelineStepData({
    required this.label,
    required this.statusColor,
    required this.state,
    this.subtitle,
    this.dateLabel,
    this.note,
    this.noteIsWarning = false,
  });

  final String label;
  final AppStatusColor statusColor;
  final StatusTimelineStepState state;

  /// Texto do passo ATUAL mostrado na zona de detalhe por baixo do traço
  /// (ex.: motivo de cancelamento). Ignorado em passos que não são o atual.
  final String? subtitle;

  /// Caption curta (ex.: "12/10") mostrada por baixo do label do nó, só em
  /// passos `completed` com data — não aparece na zona de detalhe.
  final String? dateLabel;
  final String? note;
  final bool noteIsWarning;
}

/// Duração do preenchimento do trilho quando um passo transita — bespoke a
/// este componente (docs/motion_spec.md §3, "Timeline · avanço": "1s").
const _fillDuration = Duration(milliseconds: 1000);

/// Desenho do nó (círculo) partilhado pelas duas orientações da timeline —
/// única fonte da regra "cor real do estado, nunca `AppColors.primary`
/// automaticamente" (passo futuro é o único sem estado real: contorno
/// neutro fixo, independente do `statusColor` recebido).
Widget buildTimelineNodeCircle(StatusTimelineStepData step, {required double size}) {
  final checkSize = size * 14 / 24;
  final dotSize = size * 10 / 24;
  return switch (step.state) {
    StatusTimelineStepState.completed => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: step.statusColor.foreground,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.check, color: Colors.white, size: checkSize),
      ),
    StatusTimelineStepState.current => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: step.statusColor.background,
          shape: BoxShape.circle,
          border: Border.all(color: step.statusColor.foreground, width: 2),
        ),
        child: Icon(Icons.circle, color: step.statusColor.foreground, size: dotSize),
      ),
    StatusTimelineStepState.future => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.divider, width: 2),
          shape: BoxShape.circle,
        ),
      ),
  };
}

/// Linhas da "zona de detalhe" por baixo do traço horizontal — ponto único
/// onde vive informação que não cabe junto de cada nó: o subtitle do passo
/// ATUAL (ex. motivo de cancelamento) e a note de qualquer passo (ex. aviso
/// de remarcação pendente ligado ao passo "Proposta aceite", que pode já não
/// ser o atual). Ver docs/decisions_log.md — conversão para horizontal.
List<Widget> _timelineDetailLines(ThemeData theme, List<StatusTimelineStepData> steps) {
  final lines = <Widget>[];

  for (final step in steps) {
    if (step.state == StatusTimelineStepState.current && step.subtitle != null) {
      lines.add(Text(
        step.subtitle!,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ));
    }
  }

  for (final step in steps) {
    if (step.note == null) continue;
    final noteColor =
        step.noteIsWarning ? AppStatusColor.waiting : AppStatusColor.success;
    lines.add(Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: noteColor.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        step.note!,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(color: noteColor.foreground),
      ),
    ));
  }

  return lines;
}

/// Timeline horizontal compacta — única variante do indicador de progresso
/// usada na app (a vertical foi removida quando todos os ecrãs passaram a
/// mostrar o indicador no topo, horizontal; ver decisions_log.md). Reaproveita
/// a mesma regra de cor dos nós ([buildTimelineNodeCircle]), o mesmo pulso do
/// nó atual (`AppPulseScale`, docs/motion_spec.md §3 "Timeline · nó atual") e
/// a mesma animação de avanço do conector (§3 "Timeline · avanço").
///
/// `subtitle`/`note` não aparecem junto do nó (a coluna de 72px não tem
/// espaço) — em vez disso, [_timelineDetailLines] reúne essa informação numa
/// zona única por baixo do traço. Datas de passos `completed` (`dateLabel`)
/// são a única excepção: cabem como caption curta sob o próprio label.
class StatusTimelineHorizontal extends StatefulWidget {
  const StatusTimelineHorizontal({super.key, required this.steps});

  final List<StatusTimelineStepData> steps;

  @override
  State<StatusTimelineHorizontal> createState() =>
      _StatusTimelineHorizontalState();
}

class _StatusTimelineHorizontalState extends State<StatusTimelineHorizontal> {
  List<StatusTimelineStepState>? _previousStates;

  @override
  void didUpdateWidget(covariant StatusTimelineHorizontal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _previousStates = oldWidget.steps.map((s) => s.state).toList();
  }

  bool _hasTransitioned(int index) {
    final previous = _previousStates;
    if (previous == null || index >= previous.length) return false;
    return previous[index] != widget.steps[index].state;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) return const SizedBox.shrink();
    final detailLines = _timelineDetailLines(Theme.of(context), widget.steps);
    final stepCount = widget.steps.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // Largura do nó fica em `_horizontalNodeColumnWidth` sempre que
            // couber (mantém o visual atual) — só encolhe o suficiente para
            // caber nos 4 passos de `buildJobTimeline` em ecrãs de 360dp com
            // cartões de margem `AppSpacing.lg` (worker_my_job_detail_view.dart
            // e o ramo não-`open` de client_job_detail_screen.dart deixavam
            // 280px disponíveis para 288px de nós fixos — overflow de 8px).
            const minConnectorWidth = 12.0;
            final idealTotal = stepCount * _horizontalNodeColumnWidth +
                (stepCount - 1) * minConnectorWidth;
            final nodeWidth = idealTotal <= constraints.maxWidth
                ? _horizontalNodeColumnWidth
                : ((constraints.maxWidth - (stepCount - 1) * minConnectorWidth) /
                        stepCount)
                    .clamp(0.0, _horizontalNodeColumnWidth);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < stepCount; i++) ...[
                  _HorizontalTimelineNode(
                    step: widget.steps[i],
                    animateFill: _hasTransitioned(i),
                    width: nodeWidth,
                  ),
                  if (i != stepCount - 1)
                    Expanded(
                      child: _HorizontalTimelineConnector(
                        step: widget.steps[i],
                        animateFill: _hasTransitioned(i),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
        if (detailLines.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          for (final line in detailLines)
            Padding(padding: const EdgeInsets.only(top: 4), child: line),
        ],
      ],
    );
  }
}

const double _horizontalNodeSize = 28;
const double _horizontalCurrentNodeSize = 36;
const double _horizontalNodeColumnWidth = 72;

class _HorizontalTimelineNode extends StatefulWidget {
  const _HorizontalTimelineNode({
    required this.step,
    required this.animateFill,
    required this.width,
  });

  final StatusTimelineStepData step;
  final bool animateFill;
  final double width;

  @override
  State<_HorizontalTimelineNode> createState() => _HorizontalTimelineNodeState();
}

class _HorizontalTimelineNodeState extends State<_HorizontalTimelineNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _popController;
  Timer? _popTimer;

  @override
  void initState() {
    super.initState();
    _popController = AnimationController(
      vsync: this,
      duration: AppMotionDuration.fast,
      value: widget.animateFill ? 0 : 1,
    );
    if (widget.animateFill) _schedulePop();
  }

  @override
  void didUpdateWidget(covariant _HorizontalTimelineNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animateFill && !oldWidget.animateFill) {
      _popController.value = 0;
      _schedulePop();
    }
  }

  void _schedulePop() {
    _popTimer?.cancel();
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      _popController.value = 1;
      return;
    }
    _popTimer = Timer(_fillDuration, () {
      if (mounted) _popController.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _popTimer?.cancel();
    _popController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final step = widget.step;
    final isFuture = step.state == StatusTimelineStepState.future;
    final isCurrent = step.state == StatusTimelineStepState.current;
    final size = isCurrent ? _horizontalCurrentNodeSize : _horizontalNodeSize;
    final labelColor =
        isFuture ? AppStatusColor.neutral.foreground : step.statusColor.foreground;

    return SizedBox(
      width: widget.width,
      child: Column(
        children: [
          SizedBox(
            height: _horizontalCurrentNodeSize,
            child: Center(
              child: ScaleTransition(
                scale: CurvedAnimation(
                  parent: _popController,
                  curve: AppMotionCurve.standard,
                ),
                child: AppPulseScale(
                  enabled: isCurrent,
                  child: buildTimelineNodeCircle(step, size: size),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            step.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: labelColor,
              fontWeight: isFuture ? FontWeight.w500 : FontWeight.w700,
            ),
          ),
          if (step.dateLabel != null) ...[
            const SizedBox(height: 1),
            Text(
              step.dateLabel!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: AppColors.textSecondary, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}

class _HorizontalTimelineConnector extends StatelessWidget {
  const _HorizontalTimelineConnector({required this.step, required this.animateFill});

  final StatusTimelineStepData step;
  final bool animateFill;

  @override
  Widget build(BuildContext context) {
    final targetProgress =
        step.state == StatusTimelineStepState.future ? 0.0 : 1.0;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        (disableAnimations || !animateFill) ? Duration.zero : _fillDuration;

    return Padding(
      // Centra o traço na altura do centro dos círculos — todos os nós
      // reservam a mesma altura (`_horizontalCurrentNodeSize`), mesmo os
      // círculos mais pequenos (completed/future), por isso este valor é
      // fixo independentemente do tamanho real do círculo de cada lado.
      padding: const EdgeInsets.only(top: _horizontalCurrentNodeSize / 2 - 1),
      child: SizedBox(
        height: 2,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppColors.divider),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: targetProgress),
              duration: duration,
              curve: AppMotionCurve.enter,
              builder: (context, animatedProgress, child) {
                return FractionallySizedBox(
                  widthFactor: animatedProgress,
                  alignment: Alignment.centerLeft,
                  child: child,
                );
              },
              child: ColoredBox(color: step.statusColor.foreground),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cartão que envolve [StatusTimelineHorizontal] com o fundo/raio partilhado
/// por todos os ecrãs de detalhe de job — extraído de duas implementações
/// privadas quase idênticas (`client_job_detail_screen.dart` e
/// `client_scheduled_job_detail_screen.dart`) ao levar o indicador horizontal
/// para os ramos que ainda usavam a timeline vertical (ver decisions_log.md).
///
/// `supportingLabel` é texto adicional independente dos passos — ex.: o
/// aviso de expiração do ramo `open` ou a frase "Serviço agendado para..."
/// de `client_scheduled_job_detail_screen.dart` — sempre mostrado (quando
/// não nulo), distinto da zona de detalhe por passo.
class StatusTimelineCard extends StatelessWidget {
  const StatusTimelineCard({
    super.key,
    required this.steps,
    this.supportingLabel,
    this.supportingLabelColor,
  });

  final List<StatusTimelineStepData> steps;
  final String? supportingLabel;
  final Color? supportingLabelColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          StatusTimelineHorizontal(steps: steps),
          if (supportingLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              supportingLabel!,
              textAlign: TextAlign.center,
              style: textTheme.labelMedium?.copyWith(
                color: supportingLabelColor ?? AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
