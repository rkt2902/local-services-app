import 'package:flutter/material.dart';

import '../router/app_back_navigation.dart';
import '../theme/app_colors.dart';

/// Botão de voltar partilhado para `AppBar.leading` em ecrãs de sub-fluxo.
/// Substitui o padrão ad-hoc `IconButton(onPressed: () => context.pop())`
/// por [goBackOrToRoleHome] — pop normal quando há stack, senão vai para o
/// início do papel atual em vez de não fazer nada (ver
/// `core/router/app_back_navigation.dart`).
class AppBackButton extends StatelessWidget {
  const AppBackButton({
    super.key,
    this.color = AppColors.textPrimary,
    this.tooltip = 'Voltar',
    this.fallbackLocation,
  });

  final Color color;
  final String tooltip;

  /// Destino quando não há stack para desfazer. `null` = home do papel
  /// ([goBackOrToRoleHome]); ex.: `'/login'` nos ecrãs de autenticação.
  final String? fallbackLocation;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => fallbackLocation == null
          ? goBackOrToRoleHome(context)
          : goBackOr(context, fallbackLocation!),
      tooltip: tooltip,
      icon: Icon(Icons.arrow_back_rounded, color: color),
    );
  }
}
