import 'agenda_day_view_data.dart';
import 'widgets/agenda_entry_card.dart';

/// Dados já prontos da vista Semana (design S1 a S3). Tudo é calculado pelo
/// presenter (`agenda_week_presenter.dart`); a vista não formata nem decide.

/// Um dia da faixa de 7.
class AgendaWeekDayViewData {
  const AgendaWeekDayViewData({
    required this.date,
    required this.weekdayLetter,
    required this.dayNumber,
    required this.isToday,
    required this.unavailable,
    required this.hasOverlap,
    required this.dots,
  });

  final DateTime date;

  /// "S", "T", "Q".
  final String weekdayLetter;

  /// "28".
  final String dayNumber;
  final bool isToday;

  /// Indisponível o dia todo: célula riscada.
  final bool unavailable;

  /// Horas que se cruzam: triângulo âmbar.
  final bool hasOverlap;

  /// Um ponto por entrada, pela ordem da hora. A vista mostra 3 e "+N".
  final List<AgendaCardKind> dots;
}

/// Uma linha da lista de um dia: uma entrada ou um grupo que coincide.
class AgendaWeekItem {
  const AgendaWeekItem.entry(AgendaDayEntryViewData this.entry) : group = null;

  const AgendaWeekItem.group(AgendaDayOverlapGroupViewData this.group)
    : entry = null;

  final AgendaDayEntryViewData? entry;
  final AgendaDayOverlapGroupViewData? group;
}

/// Um dia na lista da Semana. Sem [items], é a linha "Livre".
class AgendaWeekSectionViewData {
  const AgendaWeekSectionViewData({
    required this.date,
    required this.label,
    required this.isToday,
    required this.hasOverlap,
    required this.items,
    this.countLabel,
  });

  final DateTime date;

  /// "Terça, 28 out".
  final String label;

  /// "3 trabalhos", "1 proposta", "indisponível"; nulo no dia livre.
  final String? countLabel;
  final bool isToday;
  final bool hasOverlap;
  final List<AgendaWeekItem> items;

  bool get isFree => items.isEmpty;
}

/// Aviso no topo da lista (S2): "Quinta: 2 trabalhos ao mesmo tempo às
/// 14:00". "Ver o dia" abre o Hoje de [day] já no conflito.
class AgendaWeekOverlapViewData {
  const AgendaWeekOverlapViewData({required this.day, required this.label});

  final DateTime day;
  final String label;
}

class AgendaWeekContentViewData {
  const AgendaWeekContentViewData({
    required this.summaryLabel,
    required this.days,
    required this.sections,
    this.overlap,
  });

  /// "7 trabalhos · 1 proposta · ≈ 600 a 640 €"; vazio na semana livre.
  final String summaryLabel;

  /// Sempre 7, de segunda a domingo.
  final List<AgendaWeekDayViewData> days;

  /// Sempre 7, pela mesma ordem.
  final List<AgendaWeekSectionViewData> sections;
  final AgendaWeekOverlapViewData? overlap;

  /// Semana livre (S3): sem dia escolhido, sem resumo.
  bool get isEmpty => sections.every((s) => s.isFree);
}
