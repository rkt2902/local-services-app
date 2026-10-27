import '../data/agenda_entry_model.dart';

/// Deteção de sobreposições da Agenda (plano de 26/10, secção 5). Lógica
/// pura, sem Flutter nem Supabase: recebe as entradas já lidas por
/// `get_worker_agenda` e diz o que coincide. Nunca bloqueia nada; quem
/// chama decide se mostra só a nota ou também a confirmação (só no forte).
abstract final class AgendaConflictRules {
  /// Duração assumida quando um trabalho da app ou uma proposta não tem fim.
  static const appDefaultMinutes = 120;

  /// Duração assumida numa entrada de fora da app sem duração.
  static const externalDefaultMinutes = 60;

  /// Menos do que isto entre dois trabalhos é "pouco intervalo".
  static const shortGapMinutes = 30;

  static const _dayMinutes = 24 * 60;
}

enum AgendaConflictLevel {
  /// As horas cruzam-se, ou o dia está ocupado por inteiro.
  strong,

  /// Mesmo dia sem hora marcada, ou pouco intervalo.
  light,

  /// Coincide com uma proposta ou remarcação ainda por aceitar.
  tentative,
}

enum AgendaConflictReason { overlap, wholeDay, sameDayNoTime, shortGap }

class AgendaConflict {
  const AgendaConflict({
    required this.level,
    required this.reason,
    required this.other,
    this.overlapStart,
    this.overlapEnd,
    this.gapMinutes,
  });

  final AgendaConflictLevel level;
  final AgendaConflictReason reason;
  final AgendaEntry other;

  /// Intervalo que se cruza, em minutos, quando os dois têm hora.
  final int? overlapStart;
  final int? overlapEnd;

  /// Minutos entre os dois, no pouco intervalo.
  final int? gapMinutes;
}

/// O que se está a marcar: uma proposta, um trabalho de fora, uma
/// remarcação. [startMinutes] nulo = sem hora (dia todo ou flexível).
class AgendaSlot {
  const AgendaSlot({
    required this.date,
    this.startMinutes,
    this.durationMinutes,
    this.wholeDay = false,
    this.ignoreSourceId,
  });

  final DateTime date;
  final int? startMinutes;
  final int? durationMinutes;

  /// Ocupa o dia todo (indisponível, vários dias).
  final bool wholeDay;

  /// Não comparar com esta entrada (a própria, ao editar ou remarcar).
  final String? ignoreSourceId;
}

/// Intervalo [start, end) em minutos que a entrada ocupa no seu dia, ou
/// nulo quando não tem hora nem ocupa o dia todo.
(int, int)? occupiedMinutes(AgendaEntry e) {
  if (e.kind == AgendaEntryKind.block && !e.hasTime) {
    return (0, AgendaConflictRules._dayMinutes);
  }
  if (e.isMultiDay) return (0, AgendaConflictRules._dayMinutes);
  final start = e.startMinutes;
  if (start == null) return null;
  final fallback =
      e.kind == AgendaEntryKind.external || e.kind == AgendaEntryKind.block
      ? AgendaConflictRules.externalDefaultMinutes
      : AgendaConflictRules.appDefaultMinutes;
  final end = e.endMinutes ?? start + fallback;
  return (start, end <= start ? start + fallback : end);
}

(int, int)? _slotMinutes(AgendaSlot s, AgendaEntryKind kind) {
  if (s.wholeDay) return (0, AgendaConflictRules._dayMinutes);
  final start = s.startMinutes;
  if (start == null) return null;
  final duration =
      s.durationMinutes ??
      (kind == AgendaEntryKind.external
          ? AgendaConflictRules.externalDefaultMinutes
          : AgendaConflictRules.appDefaultMinutes);
  return (start, start + duration);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Compara [slot] com as entradas desse dia. [slotKind] escolhe a duração
/// por omissão quando o slot não a traz. Ordena do mais grave para o mais
/// leve. Entradas fechadas (concluídas, feitas) não contam.
List<AgendaConflict> conflictsForSlot(
  AgendaSlot slot,
  List<AgendaEntry> entries, {
  AgendaEntryKind slotKind = AgendaEntryKind.proposal,
}) {
  final mine = _slotMinutes(slot, slotKind);
  final result = <AgendaConflict>[];

  for (final e in entries) {
    if (!_sameDay(e.date, slot.date)) continue;
    if (e.isClosed) continue;
    if (slot.ignoreSourceId != null && e.sourceId == slot.ignoreSourceId) {
      continue;
    }
    final conflict = _compare(mine, e);
    if (conflict != null) result.add(conflict);
  }

  result.sort((a, b) {
    final byLevel = a.level.index.compareTo(b.level.index);
    if (byLevel != 0) return byLevel;
    return (occupiedMinutes(a.other)?.$1 ?? -1).compareTo(
      occupiedMinutes(b.other)?.$1 ?? -1,
    );
  });
  return result;
}

AgendaConflict? _compare((int, int)? mine, AgendaEntry other) {
  final theirs = occupiedMinutes(other);
  final tentative = other.isTentative;

  AgendaConflict build(
    AgendaConflictLevel level,
    AgendaConflictReason reason, {
    int? start,
    int? end,
    int? gap,
  }) {
    return AgendaConflict(
      level: tentative ? AgendaConflictLevel.tentative : level,
      reason: reason,
      other: other,
      overlapStart: start,
      overlapEnd: end,
      gapMinutes: gap,
    );
  }

  final otherWholeDay =
      theirs != null &&
      theirs.$1 == 0 &&
      theirs.$2 >= AgendaConflictRules._dayMinutes;
  final mineWholeDay =
      mine != null &&
      mine.$1 == 0 &&
      mine.$2 >= AgendaConflictRules._dayMinutes;
  if (otherWholeDay || mineWholeDay) {
    return build(AgendaConflictLevel.strong, AgendaConflictReason.wholeDay);
  }

  if (mine == null || theirs == null) {
    return build(AgendaConflictLevel.light, AgendaConflictReason.sameDayNoTime);
  }

  final start = mine.$1 > theirs.$1 ? mine.$1 : theirs.$1;
  final end = mine.$2 < theirs.$2 ? mine.$2 : theirs.$2;
  if (start < end) {
    return build(
      AgendaConflictLevel.strong,
      AgendaConflictReason.overlap,
      start: start,
      end: end,
    );
  }

  final gap = mine.$1 >= theirs.$2 ? mine.$1 - theirs.$2 : theirs.$1 - mine.$2;
  if (gap < AgendaConflictRules.shortGapMinutes) {
    return build(
      AgendaConflictLevel.light,
      AgendaConflictReason.shortGap,
      gap: gap,
    );
  }
  return null;
}

/// O conflito mais grave, ou nulo se o slot está livre.
AgendaConflict? worstConflict(List<AgendaConflict> conflicts) =>
    conflicts.isEmpty ? null : conflicts.first;

/// Grupo de entradas do mesmo dia cujas horas se cruzam (cartões
/// empilhados com a faixa âmbar, A4). [start]/[end] é o intervalo onde
/// coincidem todas as que se tocam ("Coincidem das 09:30 às 11:00").
class AgendaOverlapGroup {
  const AgendaOverlapGroup({
    required this.entries,
    required this.start,
    required this.end,
  });

  final List<AgendaEntry> entries;
  final int start;
  final int end;
}

/// Agrupa as entradas de um dia que se sobrepõem. Só contam as que têm hora
/// e não são tentativas nem estão fechadas; as de dia todo ficam de fora
/// (aparecem em "Sem hora marcada"). Devolve só grupos com 2 ou mais.
List<AgendaOverlapGroup> overlapGroupsForDay(List<AgendaEntry> dayEntries) {
  final timed = [
    for (final e in dayEntries)
      if (!e.isTentative && !e.isClosed && e.hasTime && !e.isMultiDay) e,
  ]..sort((a, b) => a.startMinutes!.compareTo(b.startMinutes!));

  final groups = <AgendaOverlapGroup>[];
  var current = <AgendaEntry>[];
  var groupEnd = -1;

  void close() {
    if (current.length < 2) return;
    // "Coincidem das X às Y": do primeiro momento em que duas se cruzam ao
    // último, olhando para todos os pares do grupo.
    int? from;
    int? to;
    for (var i = 0; i < current.length; i++) {
      for (var j = i + 1; j < current.length; j++) {
        final a = occupiedMinutes(current[i])!;
        final b = occupiedMinutes(current[j])!;
        final s = a.$1 > b.$1 ? a.$1 : b.$1;
        final e = a.$2 < b.$2 ? a.$2 : b.$2;
        if (s >= e) continue;
        if (from == null || s < from) from = s;
        if (to == null || e > to) to = e;
      }
    }
    groups.add(
      AgendaOverlapGroup(entries: current, start: from ?? 0, end: to ?? 0),
    );
  }

  for (final e in timed) {
    final (s, end) = occupiedMinutes(e)!;
    if (current.isNotEmpty && s < groupEnd) {
      current.add(e);
      if (end > groupEnd) groupEnd = end;
    } else {
      close();
      current = [e];
      groupEnd = end;
    }
  }
  close();
  return groups;
}

/// O dia tem alguma sobreposição forte (ícone âmbar na faixa da semana, no
/// mês e no cabeçalho do dia).
bool dayHasOverlap(List<AgendaEntry> dayEntries) {
  if (overlapGroupsForDay(dayEntries).isNotEmpty) return true;
  final open = [
    for (final e in dayEntries)
      if (!e.isTentative && !e.isClosed) e,
  ];
  final wholeDay = open.where((e) {
    final m = occupiedMinutes(e);
    return m != null && m.$1 == 0 && m.$2 >= AgendaConflictRules._dayMinutes;
  });
  return wholeDay.isNotEmpty && open.length > 1;
}

/// Tempo livre entre duas entradas com hora, para a faixa "Livre das X às
/// Y" (ou "Só 15 min até ao próximo" abaixo de 30 min). Nulo se se cruzam.
int? freeMinutesBetween(AgendaEntry previous, AgendaEntry next) {
  final a = occupiedMinutes(previous);
  final b = occupiedMinutes(next);
  if (a == null || b == null) return null;
  final gap = b.$1 - a.$2;
  return gap > 0 ? gap : null;
}
