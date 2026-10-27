import '../../worker/data/service_type_model.dart';
import '../data/agenda_entry_model.dart';
import 'agenda_week_presenter.dart';
import 'agenda_week_view_data.dart';

/// Monta a vista Mês (M1 a M3): a grelha, de segunda a domingo, com os dias
/// dos meses ao lado para completar as semanas, e a lista do dia escolhido.
/// Cada dia usa o mesmo `buildAgendaDaySlice` da Semana.

const _monthNames = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

/// "Outubro 2026".
String agendaMonthLabel(DateTime month) =>
    '${_monthNames[month.month - 1]} ${month.year}';

/// Um dia da grelha.
class AgendaMonthCellViewData {
  const AgendaMonthCellViewData({required this.day, required this.inMonth});

  final AgendaWeekDayViewData day;

  /// Falso nos dias do mês anterior ou seguinte: cinzento claro, sem pontos,
  /// mas tocáveis (mudam de mês).
  final bool inMonth;
}

class AgendaMonthContentViewData {
  const AgendaMonthContentViewData({
    required this.cells,
    required this.selected,
  });

  /// 35 ou 42 células, pela ordem da grelha.
  final List<AgendaMonthCellViewData> cells;

  /// Lista por baixo da grelha: o dia escolhido.
  final AgendaWeekSectionViewData selected;
}

/// Grelha do mês de [selectedDay] e a lista desse dia. As linhas de fora
/// desse mês não aparecem (a leitura é só do mês).
AgendaMonthContentViewData buildAgendaMonth({
  required DateTime selectedDay,
  required List<AgendaEntry> entries,
  required DateTime now,
  required bool showProposals,
  required List<ServiceType> serviceTypes,
}) {
  final month = DateTime(selectedDay.year, selectedDay.month);
  final first = agendaWeekStart(month);
  final last = DateTime(month.year, month.month + 1, 0);
  final count = last.difference(first).inDays + 1;
  final cellCount = (count / 7).ceil() * 7;
  final byDay = agendaEntriesByDay(entries, showProposals: showProposals);

  final cells = <AgendaMonthCellViewData>[];
  AgendaWeekSectionViewData? selected;
  for (var i = 0; i < cellCount; i++) {
    final day = DateTime(first.year, first.month, first.day + i);
    final inMonth = day.month == month.month;
    final slice = buildAgendaDaySlice(
      day: day,
      dayEntries: inMonth ? byDay[day] ?? const [] : const [],
      now: now,
      serviceTypes: serviceTypes,
    );
    cells.add(AgendaMonthCellViewData(day: slice.cell, inMonth: inMonth));
    if (day == DateTime(selectedDay.year, selectedDay.month, selectedDay.day)) {
      selected = slice.section;
    }
  }
  return AgendaMonthContentViewData(cells: cells, selected: selected!);
}
