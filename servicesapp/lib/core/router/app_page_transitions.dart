import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_back_navigation.dart';
import '../theme/app_motion_tokens.dart';
import '../widgets/app_content_width.dart';

/// Transições de página para o router — docs/motion_spec.md §4.
///
/// As 3 funções devolvem sempre `duration.screen` + `easing.emphasized`
/// (o próprio spec diz "Todos a duration.screen com easing.emphasized" —
/// só o movimento muda entre tipos, nunca o tempo). Cada uma respeita
/// `MediaQuery.disableAnimations`, caindo para um cross-fade de 100ms
/// partilhado (ver [_reducedMotionPage]) em vez do movimento normal.
///
/// As 3 também envolvem [child] com [_wrapWithBackFallback] — cobre o
/// gesto/botão de voltar do sistema para TODAS as rotas que passam por
/// aqui de uma só vez (confirmado em app_router.dart: toda rota alcançável
/// por notificação usa um destes 3 builders). O botão de voltar da AppBar
/// é um fallback distinto ([AppBackButton]/`goBackOrToRoleHome`,
/// core/widgets/app_back_button.dart) — PopScope não intercepta um
/// `context.pop()` explícito, só o pop do sistema.

bool _disableAnimations(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// "Voltar com fallback" (ver app_back_navigation.dart) para o gesto/botão
/// de voltar do Android: deixa o pop do sistema seguir normalmente quando
/// há stack (`canPop: true` — comportamento inalterado), e só intervém
/// quando não há nada para desfazer (`canPop: false`, `didPop: false` no
/// callback), indo para o início do papel atual em vez de não fazer nada.
///
/// Usa `state.matchedLocation` (já disponível no `pageBuilder`) em vez de
/// `GoRouterState.of(context)` dentro do callback, e um [Builder] em vez do
/// `context` recebido do próprio `pageBuilder` para o `canPop`/`go` do
/// `PopScope` — confirmado por teste que o `context` do `pageBuilder` não é
/// um descendente da própria rota: `canPop()` lido a partir dele fica
/// desatualizado logo após um `push()` (via `context.push`, não ainda
/// refletido nesse `context` em particular), e `GoRouterState.of` lança
/// quando chamado assincronamente no callback. O `Builder` dá um contexto
/// que já é parte da árvore da rota, correto nos dois casos.
Widget _wrapWithBackFallback(GoRouterState state, Widget child) {
  final roleHome = roleHomeRouteFor(state.matchedLocation);
  return Builder(
    builder: (context) {
      return PopScope(
        canPop: context.canPop(),
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          context.go(roleHome);
        },
        // Largura máxima centrada em tablet/PC (web), sem efeito no
        // telemóvel — ver app_content_width.dart.
        child: AppContentWidth(child: child),
      );
    },
  );
}

/// Cross-fade de 100ms usado pelas 3 transições quando reduced-motion está
/// ativo — docs/motion_spec.md §5: "Substituir por cross-fade de 100 ms:
/// todas as transições de ecrã."
CustomTransitionPage<T> _reducedMotionPage<T>(
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage<T>(
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
/// notificação (docs/motion_spec.md §4). [T] é o que o ecrã devolve ao
/// fechar (`context.push<T>`).
CustomTransitionPage<T> buildSharedAxisPage<T>(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final wrapped = _wrapWithBackFallback(state, child);
  if (_disableAnimations(context)) return _reducedMotionPage<T>(state, wrapped);

  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: wrapped,
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
  final wrapped = _wrapWithBackFallback(state, child);
  if (_disableAnimations(context)) return _reducedMotionPage(state, wrapped);

  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: wrapped,
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
  final wrapped = _wrapWithBackFallback(state, child);
  if (_disableAnimations(context)) return _reducedMotionPage(state, wrapped);

  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: wrapped,
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

/// Slide de baixo — formulário que se abre por cima do ecrã de onde veio e
/// fecha para baixo ("Adicionar à agenda", design A8D). Mesmo tempo e curva
/// das outras transições.
CustomTransitionPage<T> buildSlideUpPage<T>(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final wrapped = _wrapWithBackFallback(state, child);
  if (_disableAnimations(context)) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: wrapped,
      transitionDuration: AppMotionDuration.instant,
      reverseTransitionDuration: AppMotionDuration.instant,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: wrapped,
    transitionDuration: AppMotionDuration.screen,
    reverseTransitionDuration: AppMotionDuration.screen,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final enter = CurvedAnimation(
        parent: animation,
        curve: AppMotionCurve.emphasized,
        reverseCurve: AppMotionCurve.exit,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(enter),
        child: child,
      );
    },
  );
}
