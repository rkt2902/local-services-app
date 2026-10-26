import '../../worker/data/service_type_model.dart';
import '../application/agenda_conflicts.dart';
import '../data/agenda_entry_model.dart';
import 'agenda_day_presenter.dart';
import 'agenda_day_preview_view_data.dart';

/// Monta a folha "Ver o dia" (A8F) a partir das linhas da agenda e do que o
/// formulário está a marcar. Tudo sai daqui pronto: ordem, quem choca com
/// quem, tempo livre e a frase de cima. A folha só desenha.

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

const _dayMinutes = 24 * 60;

/// 60 → "1 hora", 120 → "2 horas", 90 → "1 h 30", 45 → "45 min".
String agendaLongDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min';
  if (m == 0) return h == 1 ? '1 hora' : '$h horas';
  return '$h h ${m.toString().padLeft(2, '0')}';
}

String _range(int start, int end) =>
    '${formatMinutes(start)} a ${formatMinutes(end.clamp(0, _dayMinutes))}';

/// Um trabalho, uma proposta ou o fantasma na lista por hora.
class _Node {
  _Node.entry(AgendaEntry this.entry, this.start, this.end) : ghost = false;
  _Node.ghost(this.start, this.end) : entry = null, ghost = true;

  final AgendaEntry? entry;
  final bool ghost;
  final int start;
  final int end;

  /// Propostas e trabalhos fechados não se juntam aos grupos (como no Hoje).
  bool get groups => ghost || (!entry!.isTentative && !entry!.isClosed);
}

/// Mínimo e máximo do intervalo onde pelo menos dois se cruzam.
(int, int)? _crossing(List<_Node> nodes, {required bool onlyWithGhost}) {
  int? from;
  int? to;
  for (var i = 0; i < nodes.length; i++) {
    for (var j = i + 1; j < nodes.length; j++) {
      final a = nodes[i];
      final b = nodes[j];
      if (onlyWithGhost && !a.ghost && !b.ghost) continue;
      final s = a.start > b.start ? a.start : b.start;
      final e = a.end < b.end ? a.end : b.end;
      if (s >= e) continue;
      if (from == null || s < from) from = s;
      if (to == null || e > to) to = e;
    }
  }
  return from == null ? null : (from, to!);
}

/// O dia [day] na folha. [ghost] só aparece se for do mesmo dia; noutros
/// dias a folha mostra só a agenda. A entrada [AgendaDayPreviewGhost.
/// ignoreSourceId] (a que se está a editar) nunca aparece.
AgendaDayPreviewViewData buildAgendaDayPreview({
  required DateTime day,
  required List<AgendaEntry> entries,
  required List<ServiceType> serviceTypes,
  required DateTime now,
  AgendaDayPreviewGhost? ghost,
}) {
  final d = _dateOnly(day);
  final isToday = _sameDay(d, now);
  final ignore = ghost?.ignoreSourceId;
  final g = ghost != null && ghost.covers(d) ? ghost : null;

  final dayEntries = [
    for (final e in entries)
      if (_sameDay(e.date, d) && (ignore == null || e.sourceId != ignore)) e,
  ];

  String title(AgendaEntry e) => agendaEntryViewData(
    e,
    now: now,
    isToday: isToday,
    current: false,
    serviceTypes: serviceTypes,
  ).title;

  AgendaPreviewEntryItem entryItem(AgendaEntry e, {bool conflict = false}) =>
      AgendaPreviewEntryItem(
        agendaEntryViewData(
          e,
          now: now,
          isToday: isToday,
          current: false,
          serviceTypes: serviceTypes,
        ),
        conflict: conflict,
      );

  // ── O fantasma ────────────────────────────────────────────────
  (int, int)? ghostSpan;
  var ghostUntimed = false;
  var conflicts = const <AgendaConflict>[];
  if (g != null) {
    final start = g.startMinutes;
    if (g.wholeDay || start == null) {
      ghostUntimed = true;
    } else {
      final fallback = g.slotKind == AgendaEntryKind.external
          ? AgendaConflictRules.externalDefaultMinutes
          : AgendaConflictRules.appDefaultMinutes;
      ghostSpan = (start, start + (g.durationMinutes ?? fallback));
    }
    conflicts = conflictsForSlot(g.slotOn(d), dayEntries, slotKind: g.slotKind);
  }
  final strong = [
    for (final c in conflicts)
      if (c.level == AgendaConflictLevel.strong) c,
  ];
  final wholeDayHits = {
    for (final c in strong)
      if (c.reason == AgendaConflictReason.wholeDay) c.other,
  };

  String? ghostLabel;
  if (g != null) {
    final span = ghostSpan;
    ghostLabel = span != null
        ? '${g.label}, ${_range(span.$1, span.$2)}'
        : g.wholeDay || g.allDay
        ? '${g.label}, dia todo'
        : '${g.label}, sem hora marcada';
  }
  AgendaPreviewGhostItem ghostItem() =>
      AgendaPreviewGhostItem(label: ghostLabel!, conflict: strong.isNotEmpty);

  // ── Sem hora ──────────────────────────────────────────────────
  final untimed = [
    for (final e in dayEntries)
      if (!e.hasTime || e.isMultiDay) e,
  ];
  final nodes = <_Node>[
    for (final e in dayEntries)
      if (e.hasTime && !e.isMultiDay)
        _Node.entry(e, occupiedMinutes(e)!.$1, occupiedMinutes(e)!.$2),
    if (ghostSpan != null) _Node.ghost(ghostSpan.$1, ghostSpan.$2),
  ];
  // Por hora; o fantasma fica depois de quem começa à mesma hora.
  nodes.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    if (byStart != 0) return byStart;
    return (a.ghost ? 1 : 0).compareTo(b.ghost ? 1 : 0);
  });

  // ── Grupos de quem se cruza ───────────────────────────────────
  final clusters = <List<_Node>>[];
  var current = <_Node>[];
  var clusterEnd = -1;
  for (final n in nodes.where((n) => n.groups)) {
    if (current.isNotEmpty && n.start < clusterEnd) {
      current.add(n);
      if (n.end > clusterEnd) clusterEnd = n.end;
    } else {
      if (current.length > 1) clusters.add(current);
      current = [n];
      clusterEnd = n.end;
    }
  }
  if (current.length > 1) clusters.add(current);

  final items = <AgendaPreviewItem>[];
  if (untimed.isNotEmpty || (g != null && ghostUntimed)) {
    items.add(const AgendaPreviewSectionItem('Sem hora marcada'));
    if (g != null && ghostUntimed) items.add(ghostItem());
    for (final e in untimed) {
      items.add(entryItem(e, conflict: wholeDayHits.contains(e)));
    }
    if (nodes.isNotEmpty) items.add(const AgendaPreviewSectionItem('Por hora'));
  }

  void addGap(int from, int to, {bool first = false, bool last = false}) {
    final gap = to - from;
    if (gap <= 0) return;
    if (gap < AgendaConflictRules.shortGapMinutes) {
      // Antes do primeiro e depois do último não há "próximo".
      if (first || last) return;
      items.add(
        AgendaPreviewFreeItem('Só $gap min até ao próximo', short: true),
      );
    } else if (first) {
      items.add(AgendaPreviewFreeItem('Livre até às ${formatMinutes(to)}'));
    } else if (last) {
      items.add(
        AgendaPreviewFreeItem('Livre a partir das ${formatMinutes(from)}'),
      );
    } else {
      items.add(
        AgendaPreviewFreeItem(
          'Livre das ${formatMinutes(from)} às ${formatMinutes(to)}',
        ),
      );
    }
  }

  AgendaPreviewItem nodeItem(_Node n) => n.ghost
      ? ghostItem()
      : entryItem(n.entry!, conflict: wholeDayHits.contains(n.entry));

  int? previousEnd;
  for (final n in nodes) {
    final cluster = clusters.where((c) => c.contains(n)).firstOrNull;
    if (cluster != null && cluster.first != n) continue;
    final unit = cluster ?? [n];
    final start = unit.map((x) => x.start).reduce((a, b) => a < b ? a : b);
    final end = unit.map((x) => x.end).reduce((a, b) => a > b ? a : b);

    if (previousEnd == null) {
      addGap(0, start, first: true);
    } else {
      addGap(previousEnd, start);
    }

    if (cluster != null) {
      final withGhost = cluster.any((x) => x.ghost);
      final crossing =
          _crossing(cluster, onlyWithGhost: withGhost) ??
          _crossing(cluster, onlyWithGhost: false)!;
      final range =
          '${formatMinutes(crossing.$1)} às ${formatMinutes(crossing.$2)}';
      items.add(
        AgendaPreviewGroupItem(
          label: withGhost ? 'Choca das $range' : 'Coincidem das $range',
          children: [for (final x in cluster) nodeItem(x)],
        ),
      );
    } else {
      items.add(nodeItem(n));
    }
    previousEnd = previousEnd == null || end > previousEnd ? end : previousEnd;
  }
  if (previousEnd != null) addGap(previousEnd, _dayMinutes, last: true);

  // ── Frase de cima ─────────────────────────────────────────────
  var assessment = AgendaPreviewAssessment.none;
  String? assessmentLabel;
  if (g != null) {
    final worst = worstConflict(conflicts);
    if (worst == null) {
      assessment = AgendaPreviewAssessment.fits;
      assessmentLabel = _fitsLabel(ghostSpan, dayEntries);
    } else {
      final other = worst.other;
      final name = title(other);
      final span = occupiedMinutes(other);
      final hasRange = span != null && !other.isMultiDay && other.hasTime;
      final otherRange = hasRange ? ' (${_range(span.$1, span.$2)})' : '';
      switch ((worst.level, worst.reason)) {
        case (AgendaConflictLevel.strong, AgendaConflictReason.overlap):
          assessment = AgendaPreviewAssessment.conflict;
          final minutes = worst.overlapEnd! - worst.overlapStart!;
          final more = strong.length > 1
              ? ' e com mais ${strong.length - 1}'
              : '';
          assessmentLabel =
              'Choca ${agendaLongDuration(minutes)} com $name$otherRange$more.';
        case (AgendaConflictLevel.strong, _):
          assessment = AgendaPreviewAssessment.conflict;
          assessmentLabel = other.kind == AgendaEntryKind.block
              ? 'Choca com uma indisponibilidade: $name.'
              : hasRange
              ? 'Choca com $name$otherRange.'
              : 'Choca com $name, que ocupa o dia todo.';
        case (
          AgendaConflictLevel.tentative,
          AgendaConflictReason.overlap || AgendaConflictReason.wholeDay,
        ):
          assessment = AgendaPreviewAssessment.tentative;
          assessmentLabel =
              'Coincide com uma proposta enviada: $name$otherRange.';
        case (_, AgendaConflictReason.shortGap):
          assessment = AgendaPreviewAssessment.tight;
          final gap = worst.gapMinutes ?? 0;
          assessmentLabel = gap == 0
              ? 'Cabe, mas fica encostado a $name$otherRange.'
              : 'Cabe, mas fica só $gap min até $name$otherRange.';
        case _:
          assessment = AgendaPreviewAssessment.tight;
          assessmentLabel = ghostUntimed
              ? 'Já tens $name neste dia.'
              : 'Já tens $name neste dia, sem hora marcada.';
      }
    }
  }

  AgendaPreviewEmptyViewData? empty;
  if (dayEntries.isEmpty) {
    empty = g != null
        ? const AgendaPreviewEmptyViewData(
            title: 'Nada mais neste dia',
            body: 'O resto do dia está livre.',
          )
        : const AgendaPreviewEmptyViewData(
            title: 'Nada neste dia',
            body: 'O dia está todo livre.',
          );
  }

  return AgendaDayPreviewViewData(
    day: d,
    dayKey: agendaDayKey(d),
    dayLabel: agendaDayLabel(d, now),
    items: items,
    assessment: assessment,
    assessmentLabel: assessmentLabel,
    empty: empty,
    hasGhost: g != null,
  );
}

/// "Cabe. Fica 1 hora livre antes e depois." Mede até ao trabalho anterior
/// e ao seguinte que ocupam tempo (sem propostas nem fechados).
String _fitsLabel((int, int)? ghost, List<AgendaEntry> dayEntries) {
  if (ghost == null) return 'Cabe. Não tens mais nada neste dia.';
  int? before;
  int? after;
  for (final e in dayEntries) {
    if (e.isTentative || e.isClosed) continue;
    final span = occupiedMinutes(e);
    if (span == null) continue;
    if (span.$2 <= ghost.$1) {
      final gap = ghost.$1 - span.$2;
      if (before == null || gap < before) before = gap;
    }
    if (span.$1 >= ghost.$2) {
      final gap = span.$1 - ghost.$2;
      if (after == null || gap < after) after = gap;
    }
  }
  if (before == null && after == null) {
    return 'Cabe. Não tens mais nada neste dia.';
  }
  if (before != null && after != null) {
    return before == after
        ? 'Cabe. Fica ${agendaLongDuration(before)} livre antes e depois.'
        : 'Cabe. Fica ${agendaLongDuration(before)} livre antes e '
              '${agendaLongDuration(after)} depois.';
  }
  return before != null
      ? 'Cabe. Fica ${agendaLongDuration(before)} livre antes e não tens '
            'mais nada depois.'
      : 'Cabe. Não tens nada antes e fica ${agendaLongDuration(after!)} '
            'livre depois.';
}
