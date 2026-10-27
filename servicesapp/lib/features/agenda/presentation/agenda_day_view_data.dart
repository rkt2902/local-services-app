import 'package:flutter/widgets.dart';

import '../data/agenda_entry_model.dart';
import 'widgets/agenda_entry_card.dart';

/// Dados já prontos da vista Hoje (design H1 a H7). Tudo é calculado pelo
/// presenter (`agenda_day_presenter.dart`); a vista não formata nem decide.

/// Um cartão da lista do dia. [source] volta tal e qual nos callbacks, para
/// a integração saber o que abrir; a vista não o lê.
class AgendaDayEntryViewData {
  const AgendaDayEntryViewData({
    required this.source,
    required this.kind,
    required this.title,
    required this.serviceIcon,
    this.startLabel,
    this.endLabel,
    this.dayIndex,
    this.dayCount,
    this.timeToArrange = false,
    this.subtitle,
    this.amountLabel,
    this.pill,
    this.detailLabel,
    this.repeats = false,
    this.changedLabel,
    this.done = false,
    this.current = false,
    this.canOpen = true,
    this.showStart = false,
    this.showChooseTime = false,
    this.showOpenProposal = false,
    this.showWhatsApp = false,
    this.showMap = false,
  });

  final AgendaEntry source;
  final AgendaCardKind kind;
  final String title;
  final IconData serviceIcon;
  final String? startLabel;
  final String? endLabel;
  final int? dayIndex;
  final int? dayCount;
  final bool timeToArrange;
  final String? subtitle;
  final String? amountLabel;
  final AgendaCardPill? pill;
  final String? detailLabel;
  final bool repeats;
  final String? changedLabel;
  final bool done;

  /// A hora atual cai dentro deste trabalho: contorno verde de 2 px.
  final bool current;

  /// Toque no cartão abre o detalhe.
  final bool canOpen;

  /// Só no próprio dia, a partir de 1 h antes. Falso = o botão não existe.
  final bool showStart;

  /// "Marcar hora": trabalho marcado sem hora.
  final bool showChooseTime;

  /// "Ver proposta": proposta enviada.
  final bool showOpenProposal;
  final bool showWhatsApp;
  final bool showMap;
}

/// Trabalhos cujas horas se cruzam (solução B: empilhados, faixa âmbar).
class AgendaDayOverlapGroupViewData {
  const AgendaDayOverlapGroupViewData({
    required this.label,
    required this.entries,
  });

  /// "Coincidem das 14:00 às 15:30".
  final String label;
  final List<AgendaDayEntryViewData> entries;
}

enum AgendaDayItemKind {
  /// "Sem hora marcada", "Por hora".
  section,

  /// Linha de agora.
  now,

  /// "Livre das 11:00 às 14:00" ou, curto, "Só 15 min até ao próximo".
  free,

  /// Aviso no topo: "2 trabalhos ao mesmo tempo às 14:00".
  overlapAlert,
  overlapGroup,
  entry,
}

class AgendaDayItem {
  const AgendaDayItem._({
    required this.kind,
    this.label,
    this.short = false,
    this.entry,
    this.group,
  });

  const AgendaDayItem.section(String label)
    : this._(kind: AgendaDayItemKind.section, label: label);

  const AgendaDayItem.now(String time)
    : this._(kind: AgendaDayItemKind.now, label: time);

  const AgendaDayItem.free(String label, {bool short = false})
    : this._(kind: AgendaDayItemKind.free, label: label, short: short);

  const AgendaDayItem.overlapAlert(String label)
    : this._(kind: AgendaDayItemKind.overlapAlert, label: label);

  const AgendaDayItem.overlapGroup(AgendaDayOverlapGroupViewData group)
    : this._(kind: AgendaDayItemKind.overlapGroup, group: group);

  const AgendaDayItem.entry(AgendaDayEntryViewData entry)
    : this._(kind: AgendaDayItemKind.entry, entry: entry);

  final AgendaDayItemKind kind;
  final String? label;

  /// Tempo livre abaixo dos 30 min (tom info).
  final bool short;
  final AgendaDayEntryViewData? entry;
  final AgendaDayOverlapGroupViewData? group;
}

/// Dia indisponível (H4): o bloco riscado substitui a lista.
class AgendaDayUnavailabilityViewData {
  const AgendaDayUnavailabilityViewData({
    required this.source,
    required this.title,
    required this.subtitle,
    required this.description,
  });

  final AgendaEntry source;

  /// "Férias".
  final String title;

  /// "Dia todo · Dia 1 de 5".
  final String subtitle;

  /// "31 out a 4 nov. Só aparece na tua agenda."
  final String description;
}

class AgendaDayContentViewData {
  const AgendaDayContentViewData({
    required this.summaryLabel,
    required this.items,
    this.unavailability,
  });

  /// "3 trabalhos · das 09:00 às 18:00 · ≈ 120 a 180 €"; vazio no dia livre.
  final String summaryLabel;

  /// Já na ordem final. Com [unavailability], são os trabalhos que já
  /// estavam marcados nesse dia (aparecem por baixo, com aviso forte).
  final List<AgendaDayItem> items;
  final AgendaDayUnavailabilityViewData? unavailability;

  bool get isEmpty => items.isEmpty && unavailability == null;
}
