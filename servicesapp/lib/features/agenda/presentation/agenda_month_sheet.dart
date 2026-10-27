import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_sheet.dart';
import '../application/agenda_providers.dart';
import '../data/agenda_entry_model.dart';
import 'widgets/agenda_entry_card.dart';
import 'widgets/agenda_month_grid.dart';

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

/// Pontos de cada dia do mês, por tipo, pela ordem da legenda. Os
/// fechados (feitos, concluídos) não contam.
@visibleForTesting
Map<int, List<AgendaCardKind>> agendaDotsByDay(List<AgendaEntry> entries) {
  const order = [
    AgendaCardKind.app,
    AgendaCardKind.helper,
    AgendaCardKind.external,
    AgendaCardKind.proposal,
    AgendaCardKind.block,
  ];
  final byDay = <int, Set<AgendaCardKind>>{};
  for (final e in entries) {
    if (e.isClosed) continue;
    final kind = switch (e.kind) {
      AgendaEntryKind.appJob => AgendaCardKind.app,
      AgendaEntryKind.helperJob => AgendaCardKind.helper,
      AgendaEntryKind.external => AgendaCardKind.external,
      AgendaEntryKind.proposal ||
      AgendaEntryKind.reschedule => AgendaCardKind.proposal,
      AgendaEntryKind.block => AgendaCardKind.block,
    };
    byDay.putIfAbsent(e.date.day, () => {}).add(kind);
  }
  return {
    for (final MapEntry(:key, :value) in byDay.entries)
      key: [
        for (final k in order)
          if (value.contains(k)) k,
      ],
  };
}

/// Folha "Tocar na data" do Hoje: calendário do mês com pontos nos dias
/// com entradas. Devolve o dia escolhido.
class AgendaMonthSheet extends ConsumerStatefulWidget {
  const AgendaMonthSheet({required this.selectedDay, super.key});

  final DateTime selectedDay;

  @override
  ConsumerState<AgendaMonthSheet> createState() => _AgendaMonthSheetState();
}

class _AgendaMonthSheetState extends ConsumerState<AgendaMonthSheet> {
  late DateTime _month = DateTime(
    widget.selectedDay.year,
    widget.selectedDay.month,
  );

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final entries =
        ref.watch(agendaRangeProvider(agendaMonthRange(_month))).value ??
        const <AgendaEntry>[];
    final now = DateTime.now();
    final label = _month.year == now.year
        ? _monthNames[_month.month - 1]
        : '${_monthNames[_month.month - 1]} ${_month.year}';

    return AppSheet(
      title: 'Ir para um dia',
      onClose: () => Navigator.pop(context),
      child: AgendaMonthGrid(
        month: _month,
        monthLabel: label,
        selectedDay: widget.selectedDay,
        today: DateUtils.dateOnly(now),
        dotsByDay: agendaDotsByDay(entries),
        onPreviousMonth: () => _shift(-1),
        onNextMonth: () => _shift(1),
        onDaySelected: (day) => Navigator.pop(context, day),
      ),
    );
  }
}
