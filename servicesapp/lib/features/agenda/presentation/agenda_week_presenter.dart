import '../../worker/data/service_type_model.dart';
import '../application/agenda_conflicts.dart';
import '../data/agenda_entry_model.dart';
import 'agenda_day_presenter.dart';
import 'agenda_day_view_data.dart';
import 'agenda_week_view_data.dart';

/// Monta a vista Semana (S1 a S3) a partir das linhas de `get_worker_agenda`.
/// Usa os mesmos cartões e as mesmas regras de sobreposição do Hoje.

/// Iniciais dos dias, de segunda a domingo.
const agendaWeekdayLetters = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _plural(int n, String one, String many) =>
    n == 1 ? '1 $one' : '$n $many';

/// Segunda-feira da semana de [day].
DateTime agendaWeekStart(DateTime day) {
  final d = _dateOnly(day);
  return DateTime(d.year, d.month, d.day - (d.weekday - 1));
}

/// Os 7 dias da semana que começa em [weekStart].
List<DateTime> agendaWeekDays(DateTime weekStart) => [
  for (var i = 0; i < 7; i++)
    DateTime(weekStart.year, weekStart.month, weekStart.day + i),
];

/// "3 a 9 nov", "27 out a 2 nov"; noutro ano, com o ano.
String agendaWeekRangeLabel(DateTime weekStart, DateTime now) {
  final end = agendaWeekDays(weekStart).last;
  final last = agendaShortDate(end, now: now);
  if (weekStart.month == end.month && weekStart.year == end.year) {
    return '${weekStart.day} a $last';
  }
  return '${agendaShortDate(weekStart, now: now)} a $last';
}

/// Uma entrada conta uma vez no valor da semana, mesmo que ocupe vários dias.
(AgendaEntryKind, String, DateTime) _occurrence(AgendaEntry e) =>
    (e.kind, e.sourceId, e.seriesDate);

String _summary(List<AgendaEntry> entries, {required bool showProposals}) {
  final jobs = [
    for (final e in entries)
      if (!e.isTentative && e.kind != AgendaEntryKind.block) e,
  ];
  final proposals = {
    for (final e in entries)
      if (e.isTentative) _occurrence(e),
  };
  final parts = <String>[];
  if (jobs.isNotEmpty) parts.add(_plural(jobs.length, 'trabalho', 'trabalhos'));
  if (showProposals && proposals.isNotEmpty) {
    parts.add(_plural(proposals.length, 'proposta', 'propostas'));
  }

  var min = 0.0;
  var max = 0.0;
  final counted = <(AgendaEntryKind, String, DateTime)>{};
  for (final e in jobs) {
    if (!counted.add(_occurrence(e))) continue;
    min += e.amountMin ?? e.amountMax ?? 0;
    max += e.amountMax ?? e.amountMin ?? 0;
  }
  final amount = agendaAmountLabel(min, max);
  if (amount != null) parts.add(amount);
  return parts.join(' · ');
}

String? _countLabel(List<AgendaEntry> entries) {
  if (entries.isEmpty) return null;
  final jobs = entries
      .where((e) => !e.isTentative && e.kind != AgendaEntryKind.block)
      .length;
  final proposals = entries.where((e) => e.isTentative).length;
  final allDayBlock = entries.any(
    (e) => e.kind == AgendaEntryKind.block && !e.hasTime,
  );
  final parts = [
    if (allDayBlock || (jobs == 0 && proposals == 0)) 'indisponível',
    if (jobs > 0) _plural(jobs, 'trabalho', 'trabalhos'),
    if (proposals > 0) _plural(proposals, 'proposta', 'propostas'),
  ];
  return parts.join(' · ');
}

/// Um dia já montado: a célula (faixa da Semana, grelha do Mês), a lista e
/// o primeiro grupo que coincide, para o aviso.
class AgendaDaySlice {
  const AgendaDaySlice({
    required this.cell,
    required this.section,
    required this.entries,
    this.firstOverlap,
  });

  final AgendaWeekDayViewData cell;
  final AgendaWeekSectionViewData section;

  /// As linhas desse dia que contam (já sem propostas, se escondidas).
  final List<AgendaEntry> entries;
  final AgendaOverlapGroup? firstOverlap;
}

/// Linhas por dia, para montar vários dias sem filtrar a lista toda de cada
/// vez. Com [showProposals] a falso, as tentativas ficam de fora.
Map<DateTime, List<AgendaEntry>> agendaEntriesByDay(
  List<AgendaEntry> entries, {
  required bool showProposals,
}) {
  final byDay = <DateTime, List<AgendaEntry>>{};
  for (final e in entries) {
    if (!showProposals && e.isTentative) continue;
    byDay.putIfAbsent(_dateOnly(e.date), () => []).add(e);
  }
  return byDay;
}

/// Monta [day] com as suas linhas ([dayEntries], já filtradas): como no
/// Hoje, primeiro o que não tem hora (dia todo, vários dias), depois por
/// hora, com os que coincidem num só grupo.
AgendaDaySlice buildAgendaDaySlice({
  required DateTime day,
  required List<AgendaEntry> dayEntries,
  required DateTime now,
  required List<ServiceType> serviceTypes,
}) {
  final isToday = _sameDay(day, now);
  final untimed = [
    for (final e in dayEntries)
      if (!e.hasTime || e.isMultiDay) e,
  ];
  final timed = [
    for (final e in dayEntries)
      if (e.hasTime && !e.isMultiDay) e,
  ]..sort((a, b) => a.startMinutes!.compareTo(b.startMinutes!));
  final groups = overlapGroupsForDay(timed);

  AgendaDayEntryViewData view(AgendaEntry e) {
    final data = agendaEntryViewData(
      e,
      now: now,
      isToday: isToday,
      current: false,
      serviceTypes: serviceTypes,
    );
    if (e.kind != AgendaEntryKind.block || data.subtitle != null) return data;
    return AgendaDayEntryViewData(
      source: data.source,
      kind: data.kind,
      title: data.title,
      serviceIcon: data.serviceIcon,
      startLabel: data.startLabel,
      endLabel: data.endLabel,
      subtitle: 'Marcado por ti',
      pill: data.pill,
      repeats: data.repeats,
      canOpen: data.canOpen,
    );
  }

  final items = <AgendaWeekItem>[
    for (final e in untimed) AgendaWeekItem.entry(view(e)),
  ];
  for (final e in timed) {
    final group = groups.where((g) => g.entries.contains(e)).firstOrNull;
    if (group == null) {
      items.add(AgendaWeekItem.entry(view(e)));
    } else if (group.entries.first == e) {
      items.add(
        AgendaWeekItem.group(
          AgendaDayOverlapGroupViewData(
            label:
                'Coincidem das ${formatMinutes(group.start)} '
                'às ${formatMinutes(group.end)}',
            entries: [for (final x in group.entries) view(x)],
          ),
        ),
      );
    }
  }

  return AgendaDaySlice(
    entries: dayEntries,
    firstOverlap: groups.firstOrNull,
    cell: AgendaWeekDayViewData(
      date: day,
      weekdayLetter: agendaWeekdayLetters[day.weekday - 1],
      dayNumber: '${day.day}',
      isToday: isToday,
      unavailable: dayEntries.any(
        (e) => e.kind == AgendaEntryKind.block && !e.hasTime,
      ),
      hasOverlap: groups.isNotEmpty,
      dots: [
        for (final item in items)
          if (item.entry != null)
            item.entry!.kind
          else
            for (final e in item.group!.entries) e.kind,
      ],
    ),
    section: AgendaWeekSectionViewData(
      date: day,
      label: '${agendaWeekdayName(day)}, ${agendaShortDate(day, now: now)}',
      countLabel: _countLabel(dayEntries),
      isToday: isToday,
      hasOverlap: groups.isNotEmpty,
      items: items,
    ),
  );
}

/// Conteúdo da semana que começa em [weekStart] (as linhas de outros dias são
/// ignoradas). Com [showProposals] a falso, as propostas e as remarcações por
/// aceitar saem da lista, dos pontos e do resumo.
AgendaWeekContentViewData buildAgendaWeek({
  required DateTime weekStart,
  required List<AgendaEntry> entries,
  required DateTime now,
  required bool showProposals,
  required List<ServiceType> serviceTypes,
}) {
  final byDay = agendaEntriesByDay(entries, showProposals: showProposals);
  final slices = [
    for (final day in agendaWeekDays(weekStart))
      buildAgendaDaySlice(
        day: day,
        dayEntries: byDay[day] ?? const [],
        now: now,
        serviceTypes: serviceTypes,
      ),
  ];

  final overlapping = [
    for (final s in slices)
      if (s.firstOverlap != null) s,
  ];
  AgendaWeekOverlapViewData? overlap;
  if (overlapping.isNotEmpty) {
    final first = overlapping.first;
    final g = first.firstOverlap!;
    final more = overlapping.length > 1
        ? ' (e mais ${overlapping.length - 1})'
        : '';
    overlap = AgendaWeekOverlapViewData(
      day: first.cell.date,
      label:
          '${agendaWeekdayName(first.cell.date)}: ${g.entries.length} '
          'trabalhos ao mesmo tempo às ${formatMinutes(g.start)}$more',
    );
  }

  return AgendaWeekContentViewData(
    summaryLabel: _summary([
      for (final s in slices) ...s.entries,
    ], showProposals: showProposals),
    days: [for (final s in slices) s.cell],
    sections: [for (final s in slices) s.section],
    overlap: overlap,
  );
}
