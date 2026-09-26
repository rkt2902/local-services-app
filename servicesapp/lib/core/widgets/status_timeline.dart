import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion_tokens.dart';
import '../theme/app_status_color.dart';
import 'app_motion.dart';

enum StatusTimelineStepState { completed, current, future }

class StatusTimelineStepData {
  const StatusTimelineStepData({
    required this.label,
    required this.statusColor,
    required this.state,
    this.subtitle,
    this.note,
    this.noteIsWarning = false,
  });

  final String label;
  final AppStatusColor statusColor;
  final StatusTimelineStepState state;
  final String? subtitle;
  final String? note;
  final bool noteIsWarning;
}

/// Timeline vertical com estado por passo.
///
/// O nó "current" respira (`AppPulseScale`) e o conector entre passos
/// preenche-se animado quando o estado de um passo muda entre rebuilds —
/// não repete a animação em rebuilds que não alteram nenhum estado (ver
/// [_hasTransitioned]).
class StatusTimeline extends StatefulWidget {
  const StatusTimeline({super.key, required this.steps});

  final List<StatusTimelineStepData> steps;

  @override
  State<StatusTimeline> createState() => _StatusTimelineState();
}

class _StatusTimelineState extends State<StatusTimeline> {
  List<StatusTimelineStepState>? _previousStates;

  @override
  void didUpdateWidget(covariant StatusTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    _previousStates = oldWidget.steps.map((s) => s.state).toList();
  }

  /// `false` no primeiro build (nada para comparar) e sempre que o estado
  /// do passo em [index] não mudou desde o build anterior — evita repetir
  /// a animação de fill em rebuilds que não representam uma transição real.
  bool _hasTransitioned(int index) {
    final previous = _previousStates;
    if (previous == null || index >= previous.length) return false;
    return previous[index] != widget.steps[index].state;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < widget.steps.length; i++)
          _TimelineRow(
            step: widget.steps[i],
            isLast: i == widget.steps.length - 1,
            animateFill: _hasTransitioned(i),
          ),
      ],
    );
  }
}

/// Duração do preenchimento do trilho quando um passo transita — bespoke a
/// este componente (docs/motion_spec.md §3, "Timeline · avanço": "1s").
const _fillDuration = Duration(milliseconds: 1000);

class _TimelineRow extends StatefulWidget {
  const _TimelineRow({
    required this.step,
    required this.isLast,
    required this.animateFill,
  });

  final StatusTimelineStepData step;
  final bool isLast;
  final bool animateFill;

  static const _circleSize = 24.0;
  static const _lineWidth = 2.0;

  @override
  State<_TimelineRow> createState() => _TimelineRowState();
}

class _TimelineRowState extends State<_TimelineRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _popController;
  Timer? _popTimer;

  @override
  void initState() {
    super.initState();
    _popController = AnimationController(
      vsync: this,
      duration: AppMotionDuration.fast,
      // Sem transição real (primeiro build, ou rebuild sem mudança de
      // estado): o nó aparece já na escala final, sem pop.
      value: widget.animateFill ? 0 : 1,
    );
    if (widget.animateFill) _schedulePop();
  }

  @override
  void didUpdateWidget(covariant _TimelineRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animateFill && !oldWidget.animateFill) {
      _popController.value = 0;
      _schedulePop();
    }
  }

  /// O nó só "aparece com pop" DEPOIS do trilho terminar de se preencher —
  /// nunca em simultâneo (ver docs/motion_spec.md §3, "Timeline · avanço").
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
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _TimelineRow._circleSize,
            child: Column(
              children: [
                ScaleTransition(
                  scale: CurvedAnimation(
                    parent: _popController,
                    curve: AppMotionCurve.standard,
                  ),
                  child: AppPulseScale(
                    enabled:
                        widget.step.state == StatusTimelineStepState.current,
                    child: _circle(),
                  ),
                ),
                if (!widget.isLast) Expanded(child: _connector(context)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2, bottom: widget.isLast ? 0 : 16),
              child: _content(theme),
            ),
          ),
        ],
      ),
    );
  }

  StatusTimelineStepData get step => widget.step;

  // Passo concluído e atual usam sempre a cor real do estado
  // (step.statusColor) — nunca AppColors.primary automaticamente. Passo
  // futuro é o único que não representa um estado real: outline neutro fixo,
  // independentemente do statusColor recebido.
  Widget _circle() => switch (step.state) {
        StatusTimelineStepState.completed => Container(
            width: _TimelineRow._circleSize,
            height: _TimelineRow._circleSize,
            decoration: BoxDecoration(
              color: step.statusColor.foreground,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 14),
          ),
        StatusTimelineStepState.current => Container(
            width: _TimelineRow._circleSize,
            height: _TimelineRow._circleSize,
            decoration: BoxDecoration(
              color: step.statusColor.background,
              shape: BoxShape.circle,
              border: Border.all(color: step.statusColor.foreground, width: 2),
            ),
            child: Icon(Icons.circle,
                color: step.statusColor.foreground, size: 10),
          ),
        StatusTimelineStepState.future => Container(
            width: _TimelineRow._circleSize,
            height: _TimelineRow._circleSize,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.divider, width: 2),
              shape: BoxShape.circle,
            ),
          ),
      };

  /// Track de fundo (AppColors.divider) + fill animado por cima. O fill
  /// representa a mesma semântica de cor que o código anterior já usava
  /// (completed/current = cor do estado; future = sem fill) — só passou a
  /// ser um preenchimento animado em vez de um Container sólido.
  ///
  /// `height` do `SizedBox` fixa em `_circleSize` (não `double.infinity`,
  /// como esteve antes, nem sem valor nenhum) de propósito — este widget só
  /// é usado dentro de `Expanded` (ver `build()` acima), que já lhe impõe a
  /// altura esticada real no layout normal (`BoxConstraints` tight vence
  /// sempre sobre a preferência do `SizedBox`), por isso o valor exato aqui
  /// é irrelevante visualmente. O que importa é ser FINITO: `IntrinsicHeight`
  /// (o `Row` todo, no `build()` acima) precisa de uma altura intrínseca de
  /// cada filho, e:
  ///   1) com `height: double.infinity`, o próprio `SizedBox` reportava
  ///      infinito directamente — falha imediata do assert `height.isFinite`.
  ///   2) sem `height` nenhuma, o `SizedBox` delega a altura intrínseca ao
  ///      filho — e o `FractionallySizedBox` computa a sua própria altura
  ///      intrínseca como `alturaDoFilho / heightFactor`; no primeiro frame
  ///      de qualquer passo (animação a começar de `begin: 0`), `heightFactor
  ///      == animatedProgress == 0`, e essa divisão dá infinito na mesma —
  ///      mesmo assert a falhar, só que um nível mais fundo.
  /// Uma altura tight finita corta a consulta ANTES de chegar a essa divisão
  /// (`RenderConstrainedBox` devolve logo o valor tight, nunca pergunta ao
  /// filho). Em debug isto era um crash vermelho; em release (assert
  /// desligado) o infinito propagava-se pelo layout sem erro nenhum e o
  /// ecrã ficava com conteúdo em branco — o bug reportado em
  /// `client_job_detail_screen.dart` para jobs `open` e `confirmed`
  /// (qualquer timeline com 2+ passos aciona isto, porque só o último passo
  /// não tem conector).
  Widget _connector(BuildContext context) {
    final targetProgress =
        step.state == StatusTimelineStepState.future ? 0.0 : 1.0;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = (disableAnimations || !widget.animateFill)
        ? Duration.zero
        : _fillDuration;

    return Center(
      child: SizedBox(
        width: _TimelineRow._lineWidth,
        height: _TimelineRow._circleSize,
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
                  heightFactor: animatedProgress,
                  alignment: Alignment.topCenter,
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

  Widget _content(ThemeData theme) {
    final isFuture = step.state == StatusTimelineStepState.future;
    final labelStyle = isFuture
        ? theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)
        : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);

    final noteColor =
        step.noteIsWarning ? AppStatusColor.waiting : AppStatusColor.success;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(step.label, style: labelStyle),
        if (step.subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            step.subtitle!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        if (step.note != null) ...[
          const SizedBox(height: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: noteColor.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              step.note!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: noteColor.foreground,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
