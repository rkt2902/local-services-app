import 'package:flutter/material.dart';

import '../../../core/theme/app_status_presentation.dart';

/// Estado do detalhe (D1 a D5): muda o cabeçalho, o rodapé e o tom.
enum AgendaDetailState { scheduled, done, cancelled, unavailable }

/// Botão principal do rodapé de um trabalho.
enum AgendaDetailPrimary { markDone, undoDone, restore }

/// Detalhe de um trabalho de fora da app ou de uma indisponibilidade
/// (design A8E). Tudo já formatado; a vista não decide nada.
class AgendaDetailViewData {
  const AgendaDetailViewData({
    required this.state,
    required this.title,
    required this.heroIcon,
    required this.status,
    required this.showSourceBadge,
    required this.when,
    this.metaLabel,
    this.overlap,
    this.person,
    this.place,
    this.valueNotes,
    this.unavailableInfo,
    this.primary,
    this.showCancel = false,
    this.submitting = false,
  });

  final AgendaDetailState state;

  /// "Relva da D. Rosa", "Férias".
  final String title;
  final IconData heroIcon;

  /// Marcado, Feito, Cancelado ou Indisponível.
  final AppStatusPresentation status;

  /// "Fora da app" ao lado do estado (só nos trabalhos).
  final bool showSourceBadge;

  /// "Marcado como feito a 28 out, às 17:40".
  final String? metaLabel;

  final AgendaDetailOverlapViewData? overlap;
  final AgendaDetailWhenViewData when;
  final AgendaDetailPersonViewData? person;
  final AgendaDetailPlaceViewData? place;
  final AgendaDetailValueNotesViewData? valueNotes;

  /// Só nas indisponibilidades.
  final String? unavailableInfo;

  /// Nulo numa indisponibilidade (o rodapé é Apagar + Editar).
  final AgendaDetailPrimaryViewData? primary;

  /// "Cancelar este trabalho" (só num marcado).
  final bool showCancel;

  /// Uma ação está a ser gravada: os botões ficam parados.
  final bool submitting;

  bool get isUnavailable => state == AgendaDetailState.unavailable;

  /// Feito ou cancelado: o conteúdo fica mais apagado.
  bool get isMuted =>
      state == AgendaDetailState.done || state == AgendaDetailState.cancelled;
}

class AgendaDetailWhenViewData {
  const AgendaDetailWhenViewData({
    required this.primary,
    this.secondary,
    this.secondaryIcon,
    this.exceptionLabel,
  });

  /// "Quarta, 28 out · 16:30 a 17:30", "10 a 14 nov · dia inteiro".
  final String primary;

  /// "Repete todas as quartas, até 31 mar", "Próximo: quarta, 4 nov",
  /// "Terça a sábado · 5 dias".
  final String? secondary;
  final IconData? secondaryIcon;

  /// "Mudado só este dia".
  final String? exceptionLabel;
}

class AgendaDetailPersonViewData {
  const AgendaDetailPersonViewData({
    required this.name,
    required this.hasWhatsApp,
  });

  final String name;

  /// Só com telefone. Nunca há botão de ligar.
  final bool hasWhatsApp;
}

class AgendaDetailPlaceViewData {
  const AgendaDetailPlaceViewData({
    required this.address,
    required this.canOpenMap,
  });

  final String address;
  final bool canOpenMap;
}

class AgendaDetailValueNotesViewData {
  const AgendaDetailValueNotesViewData({
    required this.sectionTitle,
    this.value,
    this.notes,
  });

  /// "Valor e notas", "Valor" ou "Notas".
  final String sectionTitle;

  /// "25 € combinado".
  final String? value;
  final String? notes;
}

class AgendaDetailOverlapViewData {
  const AgendaDetailOverlapViewData({
    required this.title,
    required this.detail,
  });

  /// "Coincide com outro trabalho."
  final String title;

  /// "Poda de sebes, 17:00 a 18:00 (app)".
  final String detail;
}

class AgendaDetailPrimaryViewData {
  const AgendaDetailPrimaryViewData({
    required this.kind,
    required this.label,
    required this.icon,
  });

  final AgendaDetailPrimary kind;
  final String label;
  final IconData icon;

  /// "Afinal não foi feito" e "Repor" são contornados; o feito é cheio.
  bool get filled => kind == AgendaDetailPrimary.markDone;
}

/// Texto do diálogo de apagar (D6), já com os dias escolhidos.
class AgendaDeleteConfirmData {
  const AgendaDeleteConfirmData({required this.title, required this.message});

  final String title;
  final String message;
}
