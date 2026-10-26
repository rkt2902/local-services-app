import 'package:flutter/material.dart';

import '../../../core/widgets/service_icon.dart';
import '../../worker/application/worker_job_rules.dart';
import '../../worker/data/service_type_model.dart';
import '../application/agenda_conflicts.dart';
import '../data/agenda_entry_model.dart';
import 'agenda_day_view_data.dart';
import 'widgets/agenda_entry_card.dart';

/// Monta a vista Hoje (H1 a H7) a partir das linhas de `get_worker_agenda`.
/// Tudo o que a vista mostra sai daqui já pronto: ordem, sobreposições,
/// tempo livre, linha de agora, "Iniciar" e textos.

const _weekdays = [
  'segunda',
  'terça',
  'quarta',
  'quinta',
  'sexta',
  'sábado',
  'domingo',
];

const _months = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// "2026-10-28": chave estável do dia (troca de dia, scroll para agora).
String agendaDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// "28 out"; noutro ano, "28 out 2027".
String agendaShortDate(DateTime day, {DateTime? now}) {
  final base = '${day.day} ${_months[day.month - 1]}';
  return now != null && day.year != now.year ? '$base ${day.year}' : base;
}

/// "Hoje, terça 28 out", "Amanhã, quarta 29 out", "Sexta, 31 out".
String agendaDayLabel(DateTime day, DateTime now) {
  final d = _dateOnly(day);
  final diff = d.difference(_dateOnly(now)).inDays;
  final weekday = _weekdays[d.weekday - 1];
  final date = agendaShortDate(d, now: now);
  return switch (diff) {
    0 => 'Hoje, $weekday $date',
    1 => 'Amanhã, $weekday $date',
    -1 => 'Ontem, $weekday $date',
    _ => '${_capitalize(weekday)}, $date',
  };
}

/// "60 €" quando o valor é fechado, "≈ 45 a 60 €" quando é estimado.
String? agendaAmountLabel(double? min, double? max) {
  final lo = (min ?? max)?.round();
  final hi = (max ?? min)?.round();
  if (lo == null || hi == null || hi <= 0) return null;
  return lo == hi ? '$hi €' : '≈ $lo a $hi €';
}

String _plural(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';

/// Zona curta de uma morada: "Rua A 1, Cascais" → "Cascais".
String? _area(String? label) {
  final text = label?.trim() ?? '';
  if (text.isEmpty) return null;
  return text.split(',').last.trim();
}

String? _join(List<String?> parts) {
  final kept = [
    for (final p in parts)
      if (p != null && p.trim().isNotEmpty) p.trim(),
  ];
  return kept.isEmpty ? null : kept.join(' · ');
}

/// "Todas as terças", "Todos os sábados", "De 15 em 15 dias", "Todos os
/// meses, dia 31".
String? _recurrenceLabel(AgendaEntry e) {
  final start = e.seriesDate;
  switch (e.recurrence) {
    case AgendaRecurrence.none:
      return null;
    case AgendaRecurrence.weekly:
      final w = _weekdays[start.weekday - 1];
      return start.weekday >= DateTime.saturday
          ? 'Todos os ${w}s'
          : 'Todas as ${w}s';
    case AgendaRecurrence.biweekly:
      return 'De 15 em 15 dias';
    case AgendaRecurrence.monthly:
      return 'Todos os meses, dia ${start.day}';
  }
}

AgendaCardKind _cardKind(AgendaEntry e) => switch (e.kind) {
  AgendaEntryKind.appJob => AgendaCardKind.app,
  AgendaEntryKind.helperJob => AgendaCardKind.helper,
  AgendaEntryKind.external => AgendaCardKind.external,
  AgendaEntryKind.proposal ||
  AgendaEntryKind.reschedule => AgendaCardKind.proposal,
  AgendaEntryKind.block => AgendaCardKind.block,
};

AgendaCardPill? _pill(AgendaEntry e) {
  if (e.isClosed) return AgendaCardPill.done;
  return switch (e.kind) {
    AgendaEntryKind.appJob => switch (e.status) {
      'in_progress' => AgendaCardPill.inProgress,
      'awaiting_confirmation' => AgendaCardPill.awaitingConfirmation,
      _ => AgendaCardPill.scheduled,
    },
    AgendaEntryKind.helperJob =>
      e.status == 'in_progress'
          ? AgendaCardPill.inProgress
          : AgendaCardPill.helper,
    AgendaEntryKind.external => AgendaCardPill.external,
    AgendaEntryKind.proposal => AgendaCardPill.proposal,
    AgendaEntryKind.reschedule => null,
    AgendaEntryKind.block => AgendaCardPill.block,
  };
}

AgendaDayEntryViewData _entryView(
  AgendaEntry e, {
  required DateTime now,
  required bool isToday,
  required bool current,
  required List<ServiceType> serviceTypes,
}) {
  final serviceName = serviceTypes
      .where((t) => t.id == e.serviceTypeId)
      .firstOrNull
      ?.name;
  final kind = _cardKind(e);
  final done = e.isClosed;
  final multiDay = e.isMultiDay;
  final hasPhone = (e.personPhone ?? '').trim().isNotEmpty;
  final hasPlace =
      (e.locationLat != null && e.locationLng != null) ||
      (e.locationLabel ?? '').trim().isNotEmpty;

  final title = switch (e.kind) {
    AgendaEntryKind.external ||
    AgendaEntryKind.block => e.title ?? serviceName ?? 'Trabalho',
    _ => serviceName ?? 'Trabalho',
  };

  final subtitle = switch (e.kind) {
    AgendaEntryKind.appJob ||
    AgendaEntryKind.reschedule => _join([_area(e.locationLabel), e.personName]),
    AgendaEntryKind.helperJob => _join([
      _area(e.locationLabel),
      e.personName == null ? null : 'com ${e.personName}',
    ]),
    AgendaEntryKind.proposal => _area(e.locationLabel),
    AgendaEntryKind.external => _join([e.locationLabel, e.personName]),
    AgendaEntryKind.block => e.locationLabel,
  };

  final icon = switch (e.kind) {
    AgendaEntryKind.block => Icons.event_busy_outlined,
    _ =>
      e.serviceTypeId == null
          ? Icons.edit_note_rounded
          : serviceTypeIconFor(serviceTypes, e.serviceTypeId),
  };

  final start = e.startMinutes;
  final end = start == null ? null : occupiedMinutes(e)?.$2;

  final confirmedUnstarted =
      e.kind == AgendaEntryKind.appJob && e.status == 'confirmed';
  // Regra do detalhe do trabalho: a partir de 1 h antes, e só no próprio
  // dia (depois disso o trabalho está em atraso e trata-se no detalhe).
  final showStart =
      confirmedUnstarted &&
      isToday &&
      !multiDay &&
      WorkerJobDayRules.canStart(
        confirmedDate: e.seriesDate,
        confirmedTime: start == null ? null : formatMinutes(start),
        confirmedFlexible: start == null,
        now: now,
      );

  return AgendaDayEntryViewData(
    source: e,
    kind: kind,
    title: title,
    serviceIcon: icon,
    startLabel: start == null ? null : formatMinutes(start),
    endLabel: end == null || end == start ? null : formatMinutes(end),
    dayIndex: multiDay ? e.dayIndex : null,
    dayCount: multiDay ? e.dayCount : null,
    timeToArrange:
        start == null &&
        !multiDay &&
        e.kind != AgendaEntryKind.external &&
        e.kind != AgendaEntryKind.block,
    subtitle: subtitle,
    amountLabel: e.kind == AgendaEntryKind.block
        ? null
        : agendaAmountLabel(e.amountMin, e.amountMax),
    pill: _pill(e),
    detailLabel: e.kind == AgendaEntryKind.reschedule
        ? 'Nova data por confirmar'
        : _recurrenceLabel(e),
    repeats: e.recurrence != AgendaRecurrence.none,
    changedLabel: e.isException ? 'Mudado só este dia' : null,
    done: done,
    current: current && !done,
    canOpen: e.jobId != null,
    showStart: showStart,
    showChooseTime:
        confirmedUnstarted && start == null && !multiDay && !showStart,
    showOpenProposal: e.kind == AgendaEntryKind.proposal,
    showWhatsApp:
        !done &&
        hasPhone &&
        e.kind != AgendaEntryKind.proposal &&
        e.kind != AgendaEntryKind.block,
    showMap: !done && hasPlace && e.kind != AgendaEntryKind.block,
  );
}

/// Um trabalho ou um grupo de trabalhos que coincidem, na lista por hora.
class _Unit {
  _Unit(this.entries, this.start, this.end, {this.group});

  final List<AgendaEntry> entries;
  final int start;
  final int end;
  final AgendaOverlapGroup? group;
}

String _summary({
  required List<AgendaEntry> real,
  required List<AgendaEntry> tentative,
  required bool showProposals,
}) {
  final jobs = [
    for (final e in real)
      if (e.kind != AgendaEntryKind.block) e,
  ];
  final parts = <String>[];
  if (jobs.isNotEmpty) parts.add(_plural(jobs.length, 'trabalho', 'trabalhos'));
  if (showProposals && tentative.isNotEmpty) {
    parts.add(_plural(tentative.length, 'proposta', 'propostas'));
  }

  final timed = [
    for (final e in jobs)
      if (e.hasTime && !e.isMultiDay) occupiedMinutes(e)!,
  ];
  if (timed.isNotEmpty) {
    final from = timed.map((t) => t.$1).reduce((a, b) => a < b ? a : b);
    final to = timed.map((t) => t.$2).reduce((a, b) => a > b ? a : b);
    parts.add('das ${formatMinutes(from)} às ${formatMinutes(to.clamp(0, 1439))}');
  }

  var min = 0.0;
  var max = 0.0;
  for (final e in jobs) {
    if (e.kind == AgendaEntryKind.block) continue;
    min += e.amountMin ?? e.amountMax ?? 0;
    max += e.amountMax ?? e.amountMin ?? 0;
  }
  final amount = agendaAmountLabel(min, max);
  if (amount != null) parts.add(amount);
  return parts.join(' · ');
}

/// Conteúdo do dia [day] a partir das linhas da agenda (pode trazer outros
/// dias: são ignorados). Com [showProposals] a falso, as propostas e as
/// remarcações por aceitar saem da lista e do resumo.
AgendaDayContentViewData buildAgendaDay({
  required DateTime day,
  required List<AgendaEntry> entries,
  required DateTime now,
  required bool showProposals,
  required List<ServiceType> serviceTypes,
}) {
  final isToday = _sameDay(day, now);
  final nowMinutes = now.hour * 60 + now.minute;

  final dayEntries = [
    for (final e in entries)
      if (_sameDay(e.date, day) && (showProposals || !e.isTentative)) e,
  ];

  final allDayBlocks = [
    for (final e in dayEntries)
      if (e.kind == AgendaEntryKind.block && !e.hasTime) e,
  ];
  final rest = [
    for (final e in dayEntries)
      if (!allDayBlocks.contains(e)) e,
  ];
  final untimed = [
    for (final e in rest)
      if (!e.hasTime || e.isMultiDay) e,
  ];
  final timed = [
    for (final e in rest)
      if (e.hasTime && !e.isMultiDay) e,
  ]..sort((a, b) => a.startMinutes!.compareTo(b.startMinutes!));

  AgendaDayEntryViewData view(AgendaEntry e, {bool current = false}) =>
      _entryView(
        e,
        now: now,
        isToday: isToday,
        current: current,
        serviceTypes: serviceTypes,
      );

  bool isCurrent(int start, int end) =>
      isToday && start <= nowMinutes && nowMinutes < end;

  // Trabalhos que coincidem viram um só bloco, na posição do primeiro.
  final groups = overlapGroupsForDay(timed);
  final grouped = {for (final g in groups) ...g.entries};
  final units = <_Unit>[];
  for (final e in timed) {
    if (grouped.contains(e)) {
      final g = groups.firstWhere((g) => g.entries.contains(e));
      if (g.entries.first != e) continue;
      final spans = g.entries.map((x) => occupiedMinutes(x)!);
      units.add(
        _Unit(
          g.entries,
          spans.map((s) => s.$1).reduce((a, b) => a < b ? a : b),
          spans.map((s) => s.$2).reduce((a, b) => a > b ? a : b),
          group: g,
        ),
      );
    } else {
      final (s, end) = occupiedMinutes(e)!;
      units.add(_Unit([e], s, end));
    }
  }

  final items = <AgendaDayItem>[];

  if (groups.isNotEmpty) {
    final g = groups.first;
    final more = groups.length > 1 ? ' (e mais ${groups.length - 1})' : '';
    items.add(
      AgendaDayItem.overlapAlert(
        '${g.entries.length} trabalhos ao mesmo tempo às '
        '${formatMinutes(g.start)}$more',
      ),
    );
  }

  if (untimed.isNotEmpty) {
    items.add(const AgendaDayItem.section('Sem hora marcada'));
    for (final e in untimed) {
      items.add(AgendaDayItem.entry(view(e)));
    }
    if (units.isNotEmpty) items.add(const AgendaDayItem.section('Por hora'));
  }

  void addGap(int from, int to, {bool sinceNow = false}) {
    final gap = to - from;
    if (gap <= 0) return;
    if (gap < AgendaConflictRules.shortGapMinutes) {
      items.add(AgendaDayItem.free('Só $gap min até ao próximo', short: true));
    } else if (sinceNow) {
      items.add(AgendaDayItem.free('Livre até às ${formatMinutes(to)}'));
    } else {
      items.add(
        AgendaDayItem.free(
          'Livre das ${formatMinutes(from)} às ${formatMinutes(to)}',
        ),
      );
    }
  }

  var nowPlaced = !isToday || units.isEmpty;
  int? previousEnd;
  for (final unit in units) {
    if (!nowPlaced && nowMinutes < unit.start) {
      items.add(AgendaDayItem.now(formatMinutes(nowMinutes)));
      nowPlaced = true;
      final from = previousEnd == null || previousEnd < nowMinutes
          ? nowMinutes
          : previousEnd;
      addGap(from, unit.start, sinceNow: true);
    } else if (previousEnd != null) {
      addGap(previousEnd, unit.start);
    }

    final group = unit.group;
    if (group != null) {
      items.add(
        AgendaDayItem.overlapGroup(
          AgendaDayOverlapGroupViewData(
            label:
                'Coincidem das ${formatMinutes(group.start)} '
                'às ${formatMinutes(group.end)}',
            entries: [
              for (final e in group.entries)
                view(
                  e,
                  current: isCurrent(
                    occupiedMinutes(e)!.$1,
                    occupiedMinutes(e)!.$2,
                  ),
                ),
            ],
          ),
        ),
      );
    } else {
      final e = unit.entries.single;
      items.add(
        AgendaDayItem.entry(
          view(e, current: !e.isTentative && isCurrent(unit.start, unit.end)),
        ),
      );
    }

    if (!nowPlaced && nowMinutes < unit.end) {
      items.add(AgendaDayItem.now(formatMinutes(nowMinutes)));
      nowPlaced = true;
    }
    previousEnd = previousEnd == null || unit.end > previousEnd
        ? unit.end
        : previousEnd;
  }
  if (!nowPlaced) items.add(AgendaDayItem.now(formatMinutes(nowMinutes)));

  final real = [
    for (final e in rest)
      if (!e.isTentative) e,
  ];
  final tentative = [
    for (final e in rest)
      if (e.isTentative) e,
  ];

  AgendaDayUnavailabilityViewData? unavailability;
  var summary = _summary(
    real: real,
    tentative: tentative,
    showProposals: showProposals,
  );
  if (allDayBlocks.isNotEmpty) {
    final b = allDayBlocks.first;
    final first = b.seriesDate;
    final last = first.add(Duration(days: b.dayCount - 1));
    final dates = b.dayCount > 1
        ? '${agendaShortDate(first, now: now)} a ${agendaShortDate(last, now: now)}.'
        : 'Só este dia.';
    unavailability = AgendaDayUnavailabilityViewData(
      source: b,
      title: b.title ?? 'Indisponível',
      subtitle: _join([
        'Dia todo',
        b.dayCount > 1 ? 'Dia ${b.dayIndex} de ${b.dayCount}' : null,
        _recurrenceLabel(b),
      ])!,
      description:
          '$dates Só aparece na tua agenda: os pedidos novos continuam a '
          'chegar.',
    );
    summary = _join(['Indisponível · dia todo', summary])!;
  }

  return AgendaDayContentViewData(
    summaryLabel: summary,
    items: items,
    unavailability: unavailability,
  );
}
