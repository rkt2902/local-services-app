import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Rota de início do papel atual, inferida do PRÓPRIO prefixo da rota
/// (`/worker/` ou `/client/`) — o mesmo padrão já usado no cross-role guard
/// do router (`app_router.dart`), sem precisar de ler sessão/Riverpod aqui.
String roleHomeRouteFor(String location) =>
    location.startsWith('/worker/') ? '/worker/home' : '/client/home';

/// "Voltar com fallback" — usado pelo botão de voltar da AppBar
/// ([AppBackButton], `core/widgets/app_back_button.dart`). O gesto/botão de
/// voltar do sistema usa a mesma regra mas chama [roleHomeRouteFor]
/// diretamente com `state.matchedLocation` (ver `app_page_transitions.dart`)
/// em vez de `GoRouterState.of(context)` — chamado de forma assíncrona a
/// partir do contexto do `pageBuilder` (não de um widget descendente da
/// própria rota), `GoRouterState.of` lança porque esse contexto não tem o
/// `InheritedWidget` de estado da rota como ancestor nessa altura.
///
/// Porquê é preciso: notificações navegam com `context.go()` de propósito
/// (ver notification_handler.dart — `push` já causou o crash de
/// `keyReservation` em pushes duplicados para a mesma rota). `go()`
/// substitui a stack toda pela rota de destino — não fica nada para
/// desfazer. Sem este fallback, voltar não fazia nada (pop sem stack).
///
/// Se houver stack para desfazer, um pop normal (ecrãs alcançados a partir
/// de um card, ou de um passo anterior do mesmo fluxo, continuam exatamente
/// iguais — nunca alterados por esta função).
void goBackOrToRoleHome(BuildContext context) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  final location = GoRouterState.of(context).matchedLocation;
  context.go(roleHomeRouteFor(location));
}
