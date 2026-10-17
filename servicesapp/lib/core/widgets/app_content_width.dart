import 'package:flutter/material.dart';

import '../theme/app_breakpoints.dart';
import '../theme/app_colors.dart';

/// Limita um ecrã a [AppBreakpoints.contentMaxWidth] e centra-o, com o
/// fundo da app e uma linha divisória de cada lado. Em telemóvel ao alto
/// (largura menor que o máximo) o ecrã ocupa a largura toda, como sempre.
///
/// A árvore de widgets é sempre a mesma, estreito ou largo: só muda a
/// borda. Assim rodar o telemóvel (ao deitar passa dos 640) não recria o
/// ecrã nem perde o que já foi escrito num formulário.
///
/// Aplicado uma única vez por rota: nos 3 builders de
/// `app_page_transitions.dart`, nas rotas com `builder` simples de
/// `app_router.dart` e à volta do conteúdo dos shells
/// (`AppAdaptiveShell`). Ecrãs novos não precisam de o usar.
class AppContentWidth extends StatelessWidget {
  const AppContentWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final constrained =
            constraints.maxWidth > AppBreakpoints.contentMaxWidth;
        // Tamanho fixo (tight) como o ecrã recebia antes: no telemóvel a
        // largura e a altura são exatamente as mesmas de sempre.
        return ColoredBox(
          color: AppColors.background,
          child: Center(
            child: SizedBox(
              width: constrained
                  ? AppBreakpoints.contentMaxWidth
                  : (constraints.hasBoundedWidth ? constraints.maxWidth : null),
              height: constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : null,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: constrained
                      ? const Border.symmetric(
                          vertical: BorderSide(color: AppColors.divider),
                        )
                      : null,
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
