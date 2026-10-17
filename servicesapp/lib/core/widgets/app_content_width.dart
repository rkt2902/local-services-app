import 'package:flutter/material.dart';

import '../theme/app_breakpoints.dart';
import '../theme/app_colors.dart';

/// Limita um ecrã a [AppBreakpoints.contentMaxWidth] e centra-o, com o
/// fundo da app e uma linha divisória de cada lado. Em telemóvel (largura
/// menor que o máximo) devolve [child] tal e qual, sem custo nenhum.
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
        if (constraints.maxWidth <= AppBreakpoints.contentMaxWidth) {
          return child;
        }
        return ColoredBox(
          color: AppColors.background,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: AppBreakpoints.contentMaxWidth,
              ),
              decoration: const BoxDecoration(
                border: Border.symmetric(
                  vertical: BorderSide(color: AppColors.divider),
                ),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
