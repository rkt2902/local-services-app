import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';
import 'package:servicesapp/core/theme/app_status_presentation.dart';

class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({
    required this.label,
    required this.statusColor,
    super.key,
  });

  AppStatusBadge.fromPresentation({
    required AppStatusPresentation presentation,
    super.key,
  })  : label = presentation.label,
        statusColor = presentation.color;

  final String label;
  final AppStatusColor statusColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: 'Estado: $label',
      child: Container(
        // SEM `alignment:` de propósito — um Container com `alignment` e um
        // único filho deixa de se ajustar ao conteúdo (hug) e passa a
        // expandir-se para ocupar todo o espaço disponível, tal como um
        // `Align`/`Center` (comportamento documentado do Container, não um
        // bug do Flutter). Era isto que fazia o badge ocupar a altura toda
        // da AppBar mesmo já envolvido em `Center` no call site — o
        // `Center` dava constraints LOOSE (0..altura da toolbar), e este
        // Container, por ter `alignment`, escolhia o máximo em vez do
        // tamanho do conteúdo. Sem `alignment`, o Container volta a
        // respeitar `minHeight` como mínimo, não como tamanho forçado.
        constraints: const BoxConstraints(
          minHeight: 28,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: statusColor.background,
          borderRadius: BorderRadius.circular(
            AppRadius.pill,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelMedium?.copyWith(
            color: statusColor.foreground,
          ),
        ),
      ),
    );
  }
}

/// Badge de estado para a AppBar (ou cabeçalhos equivalentes com leading +
/// título + badge a competir pela mesma largura, como `_ScheduledHeader` em
/// `client_scheduled_job_detail_screen.dart`). Reaproveita [AppStatusBadge]
/// (o fix de altura vive lá, por isso serve qualquer sítio que o use) e
/// acrescenta só o que é específico deste contexto apertado:
/// - margem direita consistente (`AppSpacing.md`) e `Center` para nunca
///   ficar maior que o próprio conteúdo, mesmo que a toolbar estique o
///   espaço disponível;
/// - versões curtas dos labels que, por serem longos, empurravam o título
///   para 0px de largura em telemóveis estreitos (confirmado com widget
///   test a 360–412dp) — só aqui; os mesmos badges em cards/listas
///   continuam com o texto completo de `presentation().label`.
class AppBarStatusBadge extends StatelessWidget {
  const AppBarStatusBadge({
    required this.label,
    required this.statusColor,
    super.key,
    this.trailingMargin = AppSpacing.md,
  });

  AppBarStatusBadge.fromPresentation({
    required AppStatusPresentation presentation,
    super.key,
    this.trailingMargin = AppSpacing.md,
  })  : label = presentation.label,
        statusColor = presentation.color;

  final String label;
  final AppStatusColor statusColor;

  /// `0` quando outra ação (ex.: o ícone de fechar) já vem a seguir com o
  /// seu próprio espaçamento — ver `client_job_detail_screen.dart`, ramo
  /// `open`.
  final double trailingMargin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(right: trailingMargin),
      child: Center(
        child: AppStatusBadge(
          label: _shortAppBarLabel(label),
          statusColor: statusColor,
        ),
      ),
    );
  }
}

/// Mapeamento fechado, só para a AppBar — ligado aos textos produzidos por
/// `JobStatusPresentationExtension`/`ProposalStatusPresentationExtension`
/// (core/utils/app_status_presenters.dart). Se um desses labels for
/// reescrito, confirmar se a versão nova ainda precisa de uma entrada
/// aqui (medido com widget test a 360–412dp: títulos como "Pedido
/// #50f4d012"/"Trabalho" ficavam espremidos a 0–100px de largura com os
/// labels completos, ao lado do leading + ação de fechar).
String _shortAppBarLabel(String label) => switch (label) {
      'À espera de proposta' => 'Em aberto',
      'Aguarda resposta' => 'Pendente',
      'Não selecionada' => 'Recusada',
      _ => label,
    };
