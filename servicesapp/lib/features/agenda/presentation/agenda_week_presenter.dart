import '../../worker/data/service_type_model.dart';
import '../application/agenda_conflicts.dart';
import '../data/agenda_entry_model.dart';
import 'agenda_day_presenter.dart';
import 'agenda_day_view_data.dart';
import 'agenda_week_view_data.dart';

/// Monta a vista Semana (S1 a S3) a partir das linhas de `get_worker_agenda`.
/// Usa os mesmos cartões e as mesmas regras de sobreposição do Hoje.

const _weekdayLetters = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];

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
  final days = <AgendaWeekDayViewData>[];
  final sections = <AgendaWeekSectionViewData>[];
  final weekEntries = <AgendaEntry>[];
  AgendaWeekOverlapViewData? overlap;
  var overlapDays = 0;

  for (final day in agendaWeekDays(weekStart)) {
    final isToday = _sameDay(day, now);
    final dayEntries = [
      for (final e in entries)
        if (_sameDay(e.date, day) && (showProposals || !e.isTentative)) e,
    ];
    weekEntries.addAll(dayEntries);

    // Como no Hoje: primeiro o que não tem hora (dia todo, vários dias),
    // depois por hora, com os que coincidem num só grupo.
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

    if (groups.isNotEmpty) {
      overlapDays++;
      final g = groups.first;
      overlap ??= AgendaWeekOverlapViewData(
        day: day,
        label:
            '${agendaWeekdayName(day)}: ${g.entries.length} trabalhos ao '
            'mesmo tempo às ${formatMinutes(g.start)}',
      );
    }

    days.add(
      AgendaWeekDayViewData(
        date: day,
        weekdayLetter: _weekdayLetters[day.weekday - 1],
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
    );
    sections.add(
      AgendaWeekSectionViewData(
        date: day,
        label: '${agendaWeekdayName(day)}, ${agendaShortDate(day, now: now)}',
        countLabel: _countLabel(dayEntries),
        isToday: isToday,
        hasOverlap: groups.isNotEmpty,
        items: items,
      ),
    );
  }

  final first = overlap;
  return AgendaWeekContentViewData(
    summaryLabel: _summary(weekEntries, showProposals: showProposals),
    days: days,
    sections: sections,
    overlap: first == null || overlapDays < 2
        ? first
        : AgendaWeekOverlapViewData(
            day: first.day,
            label: '${first.label} (e mais ${overlapDays - 1})',
          ),
  );
}
