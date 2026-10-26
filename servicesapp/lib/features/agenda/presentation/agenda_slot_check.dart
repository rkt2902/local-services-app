import '../../worker/data/service_type_model.dart';
import '../application/agenda_conflicts.dart';
import '../data/agenda_entry_model.dart';
import 'agenda_day_presenter.dart';
import 'agenda_entry_editor_view_data.dart';
import 'widgets/agenda_overlap.dart';

/// A Agenda nos fluxos que já existiam (A10): a nota por baixo da data em
/// Enviar proposta (M1) e Remarcar (M3), a confirmação só com conflito
/// forte e o chip do detalhe de um pedido (M2). Lógica pura: recebe as
/// linhas de `get_worker_agenda` já lidas.

/// Nota sempre; [confirm] só quando há conflito forte (as horas cruzam-se
/// com um trabalho marcado ou o dia está ocupado). Propostas e pouco
/// intervalo nunca pedem confirmação.
class AgendaSlotCheck {
  const AgendaSlotCheck({required this.note, this.confirm});

  final AgendaInlineWarningViewData note;
  final AgendaConflictDialogData? confirm;

  bool get isStrong => confirm != null;
}

String? _area(String? label) {
  final text = label?.trim() ?? '';
  if (text.isEmpty) return null;
  return text.split(',').last.trim();
}

String _range(int start, int end) =>
    '${formatMinutes(start)} a ${formatMinutes(end.clamp(0, 24 * 60))}';

String _title(AgendaEntry e, List<ServiceType> serviceTypes, DateTime now) =>
    agendaEntryViewData(
      e,
      now: now,
      isToday: false,
      current: false,
      serviceTypes: serviceTypes,
    ).title;

/// Nota e confirmação para [slot]. [confirmSummary] é o texto do diálogo
/// (vazio em Remarcar) e [continueLabel] o botão secundário ("Enviar mesmo
/// assim", "Pedir mesmo assim").
AgendaSlotCheck checkAgendaSlot({
  required AgendaSlot slot,
  required List<AgendaEntry> entries,
  required List<ServiceType> serviceTypes,
  required DateTime now,
  required String continueLabel,
  String confirmSummary = '',
}) {
  const viewDay = 'Ver o dia';
  final conflicts = conflictsForSlot(slot, entries);
  final c = conflicts.firstOrNull;
  if (c == null) {
    return AgendaSlotCheck(
      note: AgendaInlineWarningViewData(
        tone: AgendaWarningTone.success,
        message: slot.startMinutes == null
            ? 'Estás livre neste dia'
            : 'Estás livre neste horário',
        actionLabel: viewDay,
      ),
    );
  }

  final other = c.other;
  final name = _title(other, serviceTypes, now);
  final area = _area(other.locationLabel);
  final where = area == null ? '' : ', $area';
  final theirs = occupiedMinutes(other);
  final timed = other.hasTime && !other.isMultiDay && theirs != null;

  if (c.level == AgendaConflictLevel.strong) {
    final String message;
    if (other.kind == AgendaEntryKind.block) {
      message = 'Estás indisponível neste dia: $name';
    } else if (!timed) {
      message = 'Coincide com $name$where, que ocupa o dia todo';
    } else {
      message =
          'Coincide com $name$where\n${_range(theirs.$1, theirs.$2)} · '
          'já marcado';
    }
    final card = agendaEntryViewData(
      other,
      now: now,
      isToday: false,
      current: false,
      serviceTypes: serviceTypes,
    );
    return AgendaSlotCheck(
      note: AgendaInlineWarningViewData(
        tone: AgendaWarningTone.waiting,
        message: message,
        actionLabel: viewDay,
      ),
      confirm: AgendaConflictDialogData(
        title: other.kind == AgendaEntryKind.block
            ? 'Estás indisponível neste dia'
            : c.reason == AgendaConflictReason.overlap
            ? 'Já tens um trabalho a esta hora'
            : 'Já tens um trabalho neste dia',
        entryStart: card.startLabel,
        entryEnd: card.endLabel,
        entryTitle: card.title,
        entryMeta: card.subtitle,
        summary: confirmSummary,
        continueLabel: continueLabel,
      ),
    );
  }

  final String message;
  if (c.level == AgendaConflictLevel.tentative) {
    message = c.reason == AgendaConflictReason.overlap
        ? 'Também propuseste $name nesta hora'
        : 'Também propuseste $name neste dia';
  } else if (c.reason == AgendaConflictReason.shortGap && theirs != null) {
    final mine = slot.startMinutes ?? 0;
    message = mine >= theirs.$2
        ? 'Fica apertado. Acabas $name$where às '
              '${formatMinutes(theirs.$2.clamp(0, 24 * 60))}.'
        : 'Fica apertado. Começas $name$where às '
              '${formatMinutes(theirs.$1)}.';
  } else {
    message = theirs == null
        ? 'Já tens $name neste dia, sem hora marcada.'
        : 'Já tens $name neste dia, ${_range(theirs.$1, theirs.$2)}.';
  }
  return AgendaSlotCheck(
    note: AgendaInlineWarningViewData(
      tone: AgendaWarningTone.info,
      message: message,
      actionLabel: viewDay,
    ),
  );
}

/// Chip do detalhe de um pedido (M2): coincide (conflito forte), quantos
/// trabalhos já tem nesse dia, ou livre. Propostas não contam.
(AgendaAvailability, String) agendaRequestAvailability({
  required AgendaSlot slot,
  required List<AgendaEntry> entries,
}) {
  final strong = conflictsForSlot(
    slot,
    entries,
  ).where((c) => c.level == AgendaConflictLevel.strong).firstOrNull;
  if (strong != null) {
    return (
      AgendaAvailability.overlap,
      strong.other.kind == AgendaEntryKind.block
          ? 'Estás indisponível neste dia'
          : 'Coincide com um trabalho',
    );
  }
  final day = DateTime(slot.date.year, slot.date.month, slot.date.day);
  final busy = entries.where(
    (e) =>
        !e.isClosed &&
        !e.isTentative &&
        e.kind != AgendaEntryKind.block &&
        e.sourceId != slot.ignoreSourceId &&
        DateTime(e.date.year, e.date.month, e.date.day) == day,
  );
  final n = busy.map((e) => e.sourceId).toSet().length;
  if (n == 0) return (AgendaAvailability.free, 'Estás livre');
  return (
    AgendaAvailability.busyDay,
    n == 1 ? 'Já tens 1 trabalho neste dia' : 'Já tens $n trabalhos neste dia',
  );
}
