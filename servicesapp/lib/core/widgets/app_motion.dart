import 'dart:async';

import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_motion_tokens.dart';
import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';

/// Entrada vertical discreta para listas.
///
/// Cada elemento pode receber um [index] diferente para criar a entrada
/// em cascata definida no motion system (docs/motion_spec.md §3, "Lista
/// de cards"): sobe 18px e faz fade-in, com atraso incremental de
/// [AppMotionDuration.stagger] por item. A partir do 7.º item (índice
/// >= 6) entra sem atraso — evita que listas longas pareçam lentas.
///
/// Quando este widget nasce enquanto a rota-mãe ainda está a fazer a
/// transição de entrada (`duration.screen`, 300ms — docs/motion_spec.md
/// §4), o atraso incremental é ignorado e o item entra de imediato. Sem
/// isto, qualquer item cujo atraso teórico ultrapasse os 300ms da
/// transição (índice >= 3) só começaria a animar depois do ecrã já
/// parecer ter chegado — lido como duas animações em sequência em vez de
/// uma só. Fora de uma transição de rota (refresh de lista, mudança de
/// tab já assente, item adicionado depois do ecrã estar parado) a cascata
/// normal mantém-se inalterada.
class AppStaggeredEntrance extends StatefulWidget {
  const AppStaggeredEntrance({
    required this.index,
    required this.child,
    super.key,
    this.itemDelay = AppMotionDuration.stagger,
    this.duration = AppMotionDuration.fast,
  });

  final int index;
  final Widget child;
  final Duration itemDelay;
  final Duration duration;

  /// A partir deste índice, entra sem atraso (ver docs/motion_spec.md §3).
  static const int _maxStaggeredItems = 6;

  @override
  State<AppStaggeredEntrance> createState() {
    return _AppStaggeredEntranceState();
  }
}

class _AppStaggeredEntranceState extends State<AppStaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _riseOffset;

  Timer? _delayTimer;
  bool _configured = false;
  bool _disableAnimations = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    final curvedAnimation = CurvedAnimation(
      parent: _controller,
      curve: AppMotionCurve.emphasized,
    );

    _opacity = curvedAnimation;

    // 18px absolutos (não uma fração do próprio tamanho) — o valor exato
    // pedido em docs/motion_spec.md §3, independente da altura do card.
    _riseOffset = Tween<double>(
      begin: 18,
      end: 0,
    ).animate(curvedAnimation);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_configured) {
      return;
    }

    _configured = true;
    _disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (_disableAnimations) {
      _controller.value = 1;
      return;
    }

    // Rota-mãe ainda a meio da transição de entrada (`animation` só chega
    // a `isCompleted` quando o SlideTransition/FadeTransition do router —
    // app_page_transitions.dart — termina). Enquanto isso, suprime o
    // atraso incremental (ver doc do widget acima).
    final routeAnimation = ModalRoute.of(context)?.animation;
    final enteringViaRouteTransition =
        routeAnimation != null && !routeAnimation.isCompleted;

    final withinStaggerLimit =
        widget.index < AppStaggeredEntrance._maxStaggeredItems;
    final delay = (withinStaggerLimit && !enteringViaRouteTransition)
        ? Duration(
            milliseconds: widget.itemDelay.inMilliseconds * widget.index,
          )
        : Duration.zero;

    if (delay == Duration.zero) {
      _controller.forward();
      return;
    }

    _delayTimer = Timer(delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_disableAnimations) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return FadeTransition(
          opacity: _opacity,
          child: Transform.translate(
            offset: Offset(0, _riseOffset.value),
            child: child,
          ),
        );
      },
    );
  }
}

/// Transição entre conteúdos sem direção espacial ("fade-through" —
/// docs/motion_spec.md §4: trocar de tab, sem relação de avançar/recuar).
class AppFadeThroughSwitcher extends StatelessWidget {
  const AppFadeThroughSwitcher({
    required this.switchKey,
    required this.child,
    super.key,
    this.duration = AppMotionDuration.screen,
  });

  final Object switchKey;
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    // Reduced motion substitui a transição por um cross-fade de
    // AppMotionDuration.instant — nunca por duração zero (ver
    // docs/motion_spec.md §5: "transições de ecrã" continuam a existir,
    // só ficam mais rápidas).
    final effectiveDuration =
        disableAnimations ? AppMotionDuration.instant : duration;

    return AnimatedSwitcher(
      duration: effectiveDuration,
      switchInCurve: AppMotionCurve.emphasized,
      switchOutCurve: AppMotionCurve.emphasized,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            ...previousChildren,
            ?currentChild,
          ],
        );
      },
      transitionBuilder: (transitionChild, animation) {
        final scaleAnimation = Tween<double>(
          begin: 0.98,
          end: 1,
        ).animate(animation);

        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: scaleAnimation,
            alignment: Alignment.topCenter,
            child: transitionChild,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<Object>(switchKey),
        child: child,
      ),
    );
  }
}

/// Anel de destaque do nó atual de uma timeline — a "animação-assinatura"
/// do motion system (docs/motion_spec.md §3: "Timeline · nó atual").
///
/// Loop infinito de 1.8s, ease-out: um anel expande de 0 a 12px de
/// blur/spread por fora do [child] e desvanece à medida que expande — não
/// é um scale do próprio conteúdo (apesar do nome histórico do widget,
/// mantido para não obrigar a mudar todos os call sites). É o único loop
/// infinito permitido na app, e deve envolver só o nó correspondente ao
/// estado atual.
class AppPulseScale extends StatefulWidget {
  const AppPulseScale({
    required this.child,
    super.key,
    this.enabled = true,
    this.color = AppColors.primary,
  });

  final Widget child;
  final bool enabled;

  /// Cor do anel — "verde" por omissão (docs/motion_spec.md §3), não a cor
  /// de estado do nó: o pulso comunica "isto está a acontecer agora",
  /// distinto da cor semântica do próprio nó.
  final Color color;

  @override
  State<AppPulseScale> createState() {
    return _AppPulseScaleState();
  }
}

class _AppPulseScaleState extends State<AppPulseScale>
    with SingleTickerProviderStateMixin {
  static const Duration _pulseDuration = Duration(milliseconds: 1800);
  static const double _maxRingExtent = 12;

  late final AnimationController _controller;
  late final Animation<double> _ring;

  bool _disableAnimations = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: _pulseDuration,
    );

    _ring = CurvedAnimation(
      parent: _controller,
      curve: AppMotionCurve.enter,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    _updateAnimation();
  }

  @override
  void didUpdateWidget(covariant AppPulseScale oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.enabled != widget.enabled) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    if (_disableAnimations || !widget.enabled) {
      _controller
        ..stop()
        ..value = 0;
      return;
    }

    if (!_controller.isAnimating) {
      // Loop numa só direção (expande → desvanece → recomeça do zero),
      // não ping-pong — o anel "reinicia", não "respira" para trás.
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_disableAnimations || !widget.enabled) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _ring,
      child: widget.child,
      builder: (context, child) {
        final extent = _maxRingExtent * _ring.value;
        final fade = 1 - _ring.value;

        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.55 * fade),
                blurRadius: extent,
                spreadRadius: extent,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}

/// Feedback visual depois de uma operação bem-sucedida
/// (docs/motion_spec.md §3, "Check de sucesso" — tokens `sheet · reward`).
///
/// Sequência: o círculo faz pop com overshoot; o check entra 150ms depois;
/// o texto sobe com fade 200ms depois do check (350ms desde o início).
/// Deve ser apresentado apenas depois da confirmação real do controller ou
/// repository — não deve antecipar sucesso antes da resposta da operação.
class AppSuccessFeedback extends StatefulWidget {
  const AppSuccessFeedback({
    required this.visible,
    required this.message,
    super.key,
  });

  final bool visible;
  final String message;

  @override
  State<AppSuccessFeedback> createState() => _AppSuccessFeedbackState();
}

class _AppSuccessFeedbackState extends State<AppSuccessFeedback>
    with TickerProviderStateMixin {
  static const Duration _iconDelay = Duration(milliseconds: 150);
  static const Duration _textDelay = Duration(milliseconds: 350);

  late final AnimationController _circleController;
  late final AnimationController _iconController;
  late final AnimationController _textController;

  Timer? _iconTimer;
  Timer? _textTimer;
  bool _disableAnimations = false;

  @override
  void initState() {
    super.initState();

    _circleController = AnimationController(
      vsync: this,
      duration: AppMotionDuration.sheet,
    );
    _iconController = AnimationController(
      vsync: this,
      duration: AppMotionDuration.fast,
    );
    _textController = AnimationController(
      vsync: this,
      duration: AppMotionDuration.fast,
    );

    if (widget.visible) {
      _play();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void didUpdateWidget(covariant AppSuccessFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.visible && !oldWidget.visible) {
      _play();
    } else if (!widget.visible && oldWidget.visible) {
      _reset();
    }
  }

  void _play() {
    _iconTimer?.cancel();
    _textTimer?.cancel();

    // Reduced motion desliga os pops de recompensa por completo — a
    // mensagem aparece já no estado final, sem sequência (ver
    // docs/motion_spec.md §5).
    if (_disableAnimations) {
      _circleController.value = 1;
      _iconController.value = 1;
      _textController.value = 1;
      return;
    }

    _circleController.forward(from: 0);
    _iconTimer = Timer(_iconDelay, () {
      if (mounted) _iconController.forward(from: 0);
    });
    _textTimer = Timer(_textDelay, () {
      if (mounted) _textController.forward(from: 0);
    });
  }

  void _reset() {
    _iconTimer?.cancel();
    _textTimer?.cancel();
    _circleController.value = 0;
    _iconController.value = 0;
    _textController.value = 0;
  }

  @override
  void dispose() {
    _iconTimer?.cancel();
    _textTimer?.cancel();
    _circleController.dispose();
    _iconController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final backdropDuration =
        _disableAnimations ? Duration.zero : AppMotionDuration.fast;

    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: backdropDuration,
        curve: AppMotionCurve.standard,
        child: ColoredBox(
          color: AppColors.background,
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(AppSpacing.lg),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: CurvedAnimation(
                      parent: _circleController,
                      curve: AppMotionCurve.reward,
                    ),
                    child: Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppStatusColor.success.background,
                      ),
                      child: FadeTransition(
                        opacity: CurvedAnimation(
                          parent: _iconController,
                          curve: AppMotionCurve.enter,
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          size: 36,
                          color: AppStatusColor.success.foreground,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _textController,
                      curve: AppMotionCurve.enter,
                    ),
                    child: AnimatedBuilder(
                      animation: _textController,
                      builder: (context, child) {
                        final dy = 8 * (1 - AppMotionCurve.enter.transform(_textController.value));
                        return Transform.translate(
                          offset: Offset(0, dy),
                          child: child,
                        );
                      },
                      child: Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: textTheme.titleLarge?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Aplica shimmer a um skeleton existente
/// (docs/motion_spec.md §3, "Skeleton de loading": 1.3s loop, linear).
///
/// O layout do skeleton deve usar apenas cores já presentes no design system.
class AppSkeletonShimmer extends StatefulWidget {
  const AppSkeletonShimmer({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<AppSkeletonShimmer> createState() {
    return _AppSkeletonShimmerState();
  }
}

class _AppSkeletonShimmerState extends State<AppSkeletonShimmer>
    with SingleTickerProviderStateMixin {
  static const Duration _shimmerDuration = Duration(milliseconds: 1300);

  late final AnimationController _controller;

  bool _disableAnimations = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: _shimmerDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (_disableAnimations) {
      _controller
        ..stop()
        ..value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_disableAnimations) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, shimmerChild) {
        // _controller não tem curva aplicada — value avança linearmente
        // (0→1 em linha reta), como pede "shimmer ... linear".
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(
                -1.4 + (_controller.value * 2.8),
                0,
              ),
              end: Alignment(
                -0.4 + (_controller.value * 2.8),
                0,
              ),
              colors: const [
                AppColors.divider,
                AppColors.background,
                AppColors.divider,
              ],
              stops: const [0, 0.5, 1],
            ).createShader(bounds);
          },
          child: shimmerChild,
        );
      },
    );
  }
}
