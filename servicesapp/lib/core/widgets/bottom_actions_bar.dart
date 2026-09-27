import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Barra de ações fixa no fundo do ecrã — padrão adotado em todos os ecrãs
/// do fluxo de pedidos do cliente que têm ações principais (visto
/// originalmente em doc.txt como `_ScheduledActions`). Fica fora da área de
/// scroll, dentro do mesmo `SafeArea` do resto do body, como último filho de
/// uma `Column` cujo primeiro filho é o conteúdo scrollável em `Expanded`.
class BottomActionsBar extends StatelessWidget {
  const BottomActionsBar({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}
