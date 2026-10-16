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
  });

  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => goBackOrToRoleHome(context),
      tooltip: tooltip,
      icon: Icon(Icons.arrow_back_rounded, color: color),
    );
  }
}
