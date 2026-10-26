import '../../agenda/application/agenda_conflicts.dart';
import '../../agenda/data/agenda_entry_model.dart';
import '../../agenda/presentation/agenda_day_presenter.dart';
import '../data/service_type_model.dart';
import '../data/worker_job_board_entry_model.dart';

/// Tab Propostas (A9, R1): o dia e a hora de cada proposta ou candidatura,
/// e se choca com a Agenda. Lógica pura: recebe as linhas do board e as de
/// `get_worker_agenda` já lidas.

/// Quando é e se choca. [warning] nulo = sem aviso.
class WorkerProposalSchedule {
  const WorkerProposalSchedule({
    required this.date,
    required this.label,
    this.startMinutes,
    this.durationMinutes,
    this.warning,
  });

  final DateTime date;
  final int? startMinutes;
  final int? durationMinutes;

  /// "Sex 30 out · 09:00".
  final String label;

  /// "Coincide com Poda, Sintra, 09:00 a 12:00".
  final String? warning;
}

/// "Sex 30 out"; "Sáb 31 out".
String _shortDay(DateTime d, DateTime now) =>
    '${agendaWeekdayName(d).substring(0, 3)} ${agendaShortDate(d, now: now)}';

String? _area(String? label) {
  final text = label?.trim() ?? '';
  if (text.isEmpty) return null;
  return text.split(',').last.trim();
}

/// Dia e hora da entrada: a proposta pela linha da Agenda (tem a data e a
/// hora propostas), a candidatura pela data marcada do trabalho. Nulo
/// quando não há data (ou a proposta está fora do período lido).
WorkerProposalSchedule? workerProposalSchedule(
  WorkerJobBoardEntry e, {
  required List<AgendaEntry> agenda,
  required List<ServiceType> serviceTypes,
  required DateTime now,
}) {
  DateTime date;
  int? start;
  int? duration;
  if (e.role == WorkerJobBoardRole.helper) {
    final confirmed = e.confirmedDate;
    if (confirmed == null) return null;
    date = DateTime(confirmed.year, confirmed.month, confirmed.day);
    start = e.confirmedFlexible ? null : parseTimeMinutes(e.confirmedTime);
  } else {
    final own = agenda
        .where(
          (a) =>
              a.kind == AgendaEntryKind.proposal &&
              a.sourceId == e.entryId &&
              a.dayIndex == 1,
        )
        .firstOrNull;
    if (own == null) return null;
    date = own.date;
    start = own.startMinutes;
    final end = own.endMinutes;
    if (start != null && end != null && end > start) duration = end - start;
  }

  final conflicts = conflictsForSlot(
    AgendaSlot(
      date: date,
      startMinutes: start,
      durationMinutes: duration,
      ignoreSourceId: e.entryId,
    ),
    agenda,
  );
  // Só as horas que se cruzam (ou um dia ocupado) fazem aviso; propostas
  // enviadas e mesmo dia sem hora ficam de fora, como na Agenda.
  final worst = conflicts
      .where((c) => c.level == AgendaConflictLevel.strong)
      .firstOrNull;

  String? warning;
  if (worst != null) {
    final other = worst.other;
    final title = agendaEntryViewData(
      other,
      now: now,
      isToday: false,
      current: false,
      serviceTypes: serviceTypes,
    ).title;
    final span = occupiedMinutes(other);
    final timed = other.hasTime && !other.isMultiDay && span != null;
    if (other.kind == AgendaEntryKind.block) {
      warning = 'Estás indisponível neste dia: $title';
    } else if (!timed) {
      warning = 'Coincide com $title, que ocupa o dia todo';
    } else {
      final parts = [
        title,
        ?_area(other.locationLabel),
        '${formatMinutes(span.$1)} a ${formatMinutes(span.$2.clamp(0, 24 * 60))}',
      ];
      warning = 'Coincide com ${parts.join(', ')}';
    }
  }

  return WorkerProposalSchedule(
    date: date,
    startMinutes: start,
    durationMinutes: duration,
    label: [
      _shortDay(date, now),
      if (start != null) formatMinutes(start),
    ].join(' · '),
    warning: warning,
  );
}

/// Ordem da tab (R1): com aviso primeiro, depois pela data mais próxima;
/// sem data no fim, pela ordem da RPC. Estável.
List<T> sortWorkerProposals<T>(
  List<T> items,
  WorkerProposalSchedule? Function(T) scheduleOf,
) {
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  int rank(WorkerProposalSchedule? s) => s?.warning != null ? 0 : 1;
  indexed.sort((a, b) {
    final sa = scheduleOf(a.$2);
    final sb = scheduleOf(b.$2);
    final byWarning = rank(sa).compareTo(rank(sb));
    if (byWarning != 0) return byWarning;
    if (sa != null && sb != null) {
      final byDate = sa.date.compareTo(sb.date);
      if (byDate != 0) return byDate;
      final byTime = (sa.startMinutes ?? -1).compareTo(sb.startMinutes ?? -1);
      if (byTime != 0) return byTime;
    } else if (sa != null || sb != null) {
      return sa != null ? -1 : 1;
    }
    return a.$1.compareTo(b.$1);
  });
  return [for (final (_, item) in indexed) item];
}
