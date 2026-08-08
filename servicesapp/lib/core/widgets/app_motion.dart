import 'dart:async';

import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';

/// Entrada vertical discreta para listas.
///
/// Cada elemento pode receber um [index] diferente para criar a entrada
/// em cascata definida no motion system.
class AppStaggeredEntrance extends StatefulWidget {
  const AppStaggeredEntrance({
    required this.index,
    required this.child,
    super.key,
    this.itemDelay = const Duration(milliseconds: 120),
    this.duration = const Duration(milliseconds: 420),
  });

  final int index;
  final Widget child;
  final Duration itemDelay;
  final Duration duration;

  @override
  State<AppStaggeredEntrance> createState() {
    return _AppStaggeredEntranceState();
  }
}

class _AppStaggeredEntranceState extends State<AppStaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _position;

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
      curve: Curves.easeOutCubic,
    );

    _opacity = curvedAnimation;

    _position = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
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

    final delay = Duration(
      milliseconds:
          widget.itemDelay.inMilliseconds * widget.index,
    );

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

    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _position,
        child: widget.child,
      ),
    );
  }
}

/// Transição entre conteúdos sem direção espacial.
///
/// Deve ser usada ao trocar tabs ou conteúdos que não representam um avanço
/// ou retrocesso dentro da hierarquia.
class AppFadeThroughSwitcher extends StatelessWidget {
  const AppFadeThroughSwitcher({
    required this.switchKey,
    required this.child,
    super.key,
    this.duration = const Duration(milliseconds: 240),
  });

  final Object switchKey;
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedSwitcher(
      duration: disableAnimations ? Duration.zero : duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
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

/// Respiração discreta para o nó atual de uma timeline.
///
/// Deve envolver apenas o nó correspondente ao estado atual.
class AppPulseScale extends StatefulWidget {
  const AppPulseScale({
    required this.child,
    super.key,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<AppPulseScale> createState() {
    return _AppPulseScaleState();
  }
}

class _AppPulseScaleState extends State<AppPulseScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  bool _disableAnimations = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _scale = Tween<double>(
      begin: 1,
      end: 1.08,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
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
      _controller.repeat(reverse: true);
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

    return ScaleTransition(
      scale: _scale,
      child: widget.child,
    );
  }
}

/// Feedback visual depois de uma operação bem-sucedida.
///
/// Deve ser apresentado apenas depois da confirmação real do controller ou
/// repository. Não deve antecipar sucesso antes da resposta da operação.
class AppSuccessFeedback extends StatelessWidget {
  const AppSuccessFeedback({
    required this.visible,
    required this.message,
    super.key,
  });

  final bool visible;
  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final duration = disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 300);

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: duration,
        curve: Curves.easeOut,
        child: ColoredBox(
          color: AppColors.background,
          child: Center(
            child: AnimatedScale(
              scale: visible ? 1 : 0.82,
              duration: duration,
              curve: Curves.easeOutBack,
              child: Container(
                margin: const EdgeInsets.all(AppSpacing.lg),
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(
                    AppRadius.card,
                  ),
                  border: Border.all(
                    color: AppColors.divider,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppStatusColor.success.background,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 36,
                        color: AppStatusColor.success.foreground,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Aplica shimmer a um skeleton existente.
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
  late final AnimationController _controller;

  bool _disableAnimations = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
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
