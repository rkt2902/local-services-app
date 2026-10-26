import 'package:flutter/material.dart';

import '../../../core/widgets/app_sheet.dart';
import 'widgets/agenda_legend.dart';

/// Folha "O que significam as cores?" (A8G, P3). A mesma abre pelo botão
/// "Cores" do topo e pelo cartão da primeira abertura. Fecha com "Percebi",
/// tocando fora ou puxando para baixo.
Future<void> showAgendaLegendSheet(BuildContext context) {
  return AppSheet.show<void>(
    context,
    builder: (sheetContext) => AppSheet(
      title: 'O que significam as cores?',
      onClose: () => Navigator.pop(sheetContext),
      primaryActionLabel: 'Percebi',
      onPrimaryAction: () => Navigator.pop(sheetContext),
      child: const AgendaLegendSheet(showTitle: false),
    ),
  );
}
