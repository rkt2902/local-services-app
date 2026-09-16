import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_motion_tokens.dart';

/// Transições de página para o router — docs/motion_spec.md §4.
///
/// As 3 funções devolvem sempre `duration.screen` + `easing.emphasized`
/// (o próprio spec diz "Todos a duration.screen com easing.emphasized" —
/// só o movimento muda entre tipos, nunca o tempo). Cada uma respeita
/// `MediaQuery.disableAnimations`, caindo para um cross-fade de 100ms
/// partilhado (ver [_reducedMotionPage]) em vez do movimento normal.

bool _disableAnimations(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// Cross-fade de 100ms usado pelas 3 transições quando reduced-motion está
/// ativo — docs/motion_spec.md §5: "Substituir por cross-fade de 100 ms:
/// todas as transições de ecrã."
CustomTransitionPage<void> _reducedMotionPage(
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: AppMotionDuration.instant,
    reverseTransitionDuration: AppMotionDuration.instant,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: FadeTransition(
          opacity: Tween<double>(begin: 1, end: 0).animate(secondaryAnimation),
          child: child,
        ),
      );
    },
  );
}

/// Shared-axis (X) — desliza lateral. Passos de um mesmo fluxo com sentido
/// de avançar/recuar: wizards, passos de registo, deep-links de
/// notificação (docs/motion_spec.md §4).
CustomTransitionPage<void> buildSharedAxisPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  if (_disableAnimations(context)) return _reducedMotionPage(state, child);

  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: AppMotionDuration.screen,
    reverseTransitionDuration: AppMotionDuration.screen,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final enter = CurvedAnimation(
        parent: animation,
        curve: AppMotionCurve.emphasized,
      );
      final exit = CurvedAnimation(
        parent: secondaryAnimation,
        curve: AppMotionCurve.emphasized,
      );

      return SlideTransition(
        // Este ecrã a entrar por cima de outro que está a ser empurrado
        // (avançar): desliza da direita.
        position: Tween<Offset>(
          begin: const Offset(0.25, 0),
          end: Offset.zero,
        ).animate(enter),
        child: FadeTransition(
          opacity: enter,
          child: SlideTransition(
            // Este ecrã quando é ELE a ser coberto por um novo (avançar a
            // partir dele): desliza ligeiramente para a esquerda.
            position: Tween<Offset>(
              begin: Offset.zero,
              end: const Offset(-0.25, 0),
            ).animate(exit),
            child: FadeTransition(
              opacity: Tween<double>(begin: 1, end: 0).animate(exit),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

/// Container-transform — aproximação. Um transform "verdadeiro" (o card de
/// origem a crescer até preencher o ecrã) exige Hero com geometria da
/// origem partilhada entre todos os pontos de entrada — desproporcionado
/// aqui, porque as rotas com container-transform muitas vezes têm mais do
/// que uma origem de card (ver Parte 3) e os cards atuais são
/// texto/ícone, não imagens que beneficiem visivelmente de um morph real.
/// Fade + scale a partir do centro dá a mesma leitura de "cresceu a
/// partir de um ponto" sem essa complexidade.
CustomTransitionPage<void> buildContainerTransformPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  if (_disableAnimations(context)) return _reducedMotionPage(state, child);

  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: AppMotionDuration.screen,
    reverseTransitionDuration: AppMotionDuration.screen,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final enter = CurvedAnimation(
        parent: animation,
        curve: AppMotionCurve.emphasized,
      );
      final exit = CurvedAnimation(
        parent: secondaryAnimation,
        curve: AppMotionCurve.emphasized,
      );

      return FadeTransition(
        opacity: enter,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.90, end: 1).animate(enter),
          alignment: Alignment.center,
          child: FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0).animate(exit),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Fade-through — fade + escala leve, sem direção. Destinos sem relação
/// direta (docs/motion_spec.md §4). Mesma leitura visual de
/// `AppFadeThroughSwitcher` (core/widgets/app_motion.dart), só que entre
/// rotas do router em vez de dentro do mesmo ecrã.
CustomTransitionPage<void> buildFadeThroughPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  if (_disableAnimations(context)) return _reducedMotionPage(state, child);

  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: AppMotionDuration.screen,
    reverseTransitionDuration: AppMotionDuration.screen,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final enter = CurvedAnimation(
        parent: animation,
        curve: AppMotionCurve.emphasized,
      );
      final exit = CurvedAnimation(
        parent: secondaryAnimation,
        curve: AppMotionCurve.emphasized,
      );

      return FadeTransition(
        opacity: enter,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(enter),
          child: FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0).animate(exit),
            child: child,
          ),
        ),
      );
    },
  );
}
