import 'package:flutter/material.dart';

import '../../../core/theme/app_status_color.dart';
import '../../../core/theme/app_status_presentation.dart';
import '../../../core/widgets/service_icon.dart';
import '../../worker/data/service_type_model.dart';
import '../application/agenda_conflicts.dart';
import '../application/agenda_entry_actions.dart';
import '../application/agenda_entry_form.dart';
import '../data/agenda_calendar_entry.dart';
import '../data/agenda_entry_model.dart';
import 'agenda_day_presenter.dart';
import 'agenda_entry_detail_view_data.dart';
import 'agenda_entry_editor_view_data.dart';

/// "quarta 28 out".
String _weekdayDate(DateTime day, DateTime now) =>
    '${agendaWeekdayName(day).toLowerCase()} ${agendaShortDate(day, now: now)}';

/// "28 a 30 out", "30 out a 2 nov".
String _span(DateTime first, DateTime last, DateTime now) {
  if (first.year == last.year && first.month == last.month) {
    return '${first.day} a ${agendaShortDate(last, now: now)}';
  }
  return '${agendaShortDate(first, now: now)} a '
      '${agendaShortDate(last, now: now)}';
}

String _lowerFirst(String s) =>
    s.isEmpty ? s : '${s[0].toLowerCase()}${s.substring(1)}';

/// "25 €", "25,50 €".
String _euros(double value) => value == value.roundToDouble()
    ? '${value.round()} €'
    : '${value.toStringAsFixed(2).replaceAll('.', ',')} €';

/// "28 out, às 17:40".
String _instant(DateTime at, DateTime now) =>
    '${agendaShortDate(at, now: now)}, às '
    '${formatMinutes(at.hour * 60 + at.minute)}';

IconData _blockIcon(AgendaBlockReason reason) => switch (reason) {
  AgendaBlockReason.vacation => Icons.beach_access_outlined,
  AgendaBlockReason.dayOff => Icons.weekend_outlined,
  AgendaBlockReason.appointment => Icons.medical_services_outlined,
  AgendaBlockReason.other => Icons.event_busy_outlined,
};

/// Dia seguinte da série depois de [after], ou nulo se já acabou.
DateTime? nextCalendarOccurrence(CalendarEntry entry, DateTime after) {
  final start = DateUtils.dateOnly(entry.startsOn);
  final from = DateUtils.dateOnly(after);
  DateTime? next;
  switch (entry.recurrence) {
    case AgendaRecurrence.none:
      return null;
    case AgendaRecurrence.weekly || AgendaRecurrence.biweekly:
      final step = entry.recurrence == AgendaRecurrence.weekly ? 7 : 14;
      final passed = from.isBefore(start)
          ? -1
          : from.difference(start).inDays ~/ step;
      next = DateTime(start.year, start.month, start.day + (passed + 1) * step);
    case AgendaRecurrence.monthly:
      for (var m = 0; m < 1200; m++) {
        final lastDay = DateTime(start.year, start.month + m + 1, 0).day;
        final candidate = DateTime(
          start.year,
          start.month + m,
          start.day > lastDay ? lastDay : start.day,
        );
        if (candidate.isAfter(from)) {
          next = candidate;
          break;
        }
      }
  }
  final until = entry.recurrenceUntil;
  if (next == null || (until != null && next.isAfter(until))) return null;
  return next;
}

AgendaDetailWhenViewData _when(
  CalendarEntry entry,
  AgendaEntryForm form,
  CalendarException? exception, {
  required String state,
  required DateTime occurrence,
  required DateTime now,
}) {
  final block = entry.kind == CalendarEntryKind.block;
  final first = form.date;
  final last = form.lastDay;
  final multi = form.spanDays > 0;

  final String time;
  if (form.allDay) {
    time = 'dia inteiro';
  } else if (multi) {
    time = 'a partir das ${formatMinutes(form.startMinutes)}';
  } else {
    final start = form.startMinutes;
    final end = block
        ? form.endMinutes
        : (start + form.durationMinutes).clamp(0, 24 * 60);
    time = '${formatMinutes(start)} a ${formatMinutes(end)}';
  }
  final date = multi
      ? _span(first, last, now)
      : '${agendaWeekdayName(first)}, ${agendaShortDate(first, now: now)}';

  String? secondary;
  IconData? icon;
  if (entry.repeats) {
    icon = Icons.repeat_rounded;
    final next = state == 'done'
        ? nextCalendarOccurrence(entry, occurrence)
        : null;
    if (next != null) {
      secondary = 'Próximo: ${_weekdayDate(next, now)}';
    } else {
      final label = agendaRecurrenceLabel(entry.recurrence, entry.startsOn)!;
      final until = entry.recurrenceUntil;
      secondary =
          'Repete ${_lowerFirst(label)}'
          '${until == null ? '' : ', até ${agendaShortDate(until, now: now)}'}';
    }
  } else if (multi) {
    final days = form.spanDays + 1;
    secondary =
        '${agendaWeekdayName(first)} a ${_lowerFirst(agendaWeekdayName(last))} '
        '· $days dias';
  }

  return AgendaDetailWhenViewData(
    primary: '$date · $time',
    secondary: secondary,
    secondaryIcon: icon,
    exceptionLabel: exception != null && exception.changesFields
        ? 'Mudado só este dia'
        : null,
  );
}

AgendaDetailOverlapViewData? _overlap(
  AgendaEntryForm form,
  List<AgendaEntry> entries, {
  required String entryId,
  required List<ServiceType> serviceTypes,
  required DateTime now,
}) {
  final strong = form
      .conflicts(entries, ignoreSourceId: entryId)
      .where((c) => c.level == AgendaConflictLevel.strong)
      .toList();
  if (strong.isEmpty) return null;
  final other = strong.first.other;
  final card = agendaEntryViewData(
    other,
    now: now,
    isToday: false,
    current: false,
    serviceTypes: serviceTypes,
  );
  final theirs = occupiedMinutes(other);
  final wholeDay = theirs == null || (theirs.$1 == 0 && theirs.$2 >= 24 * 60);
  final fromApp = other.jobId != null;
  final parts = [
    card.title,
    if (!wholeDay)
      '${formatMinutes(theirs.$1)} a ${formatMinutes(theirs.$2.clamp(0, 24 * 60))}',
  ];
  final more = strong.length - 1;
  final isBlock = other.kind == AgendaEntryKind.block;
  return AgendaDetailOverlapViewData(
    title: isBlock
        ? 'Estás indisponível neste dia.'
        : 'Coincide com outro trabalho.',
    detail:
        '${parts.join(', ')}${fromApp ? ' (app)' : ''}'
        '${more > 0 ? '. E mais $more.' : ''}',
  );
}

/// Detalhe de um trabalho de fora da app ou de uma indisponibilidade, na
/// ocorrência [occurrence]. [entries] é a agenda do mês (para "Coincide
/// com…"); nula enquanto carrega.
AgendaDetailViewData buildAgendaEntryDetail({
  required CalendarEntry entry,
  required CalendarException? exception,
  required DateTime occurrence,
  required List<AgendaEntry>? entries,
  required List<ServiceType> serviceTypes,
  required DateTime now,
  bool submitting = false,
}) {
  final form = AgendaEntryForm.fromEntry(
    entry,
    occurrenceDate: occurrence,
    exception: exception,
  );
  final block = entry.kind == CalendarEntryKind.block;
  final status = calendarOccurrenceStatus(entry, exception);
  final statusAt = calendarOccurrenceStatusAt(entry, exception);
  final state = block
      ? AgendaDetailState.unavailable
      : switch (status) {
          'done' => AgendaDetailState.done,
          'cancelled' => AgendaDetailState.cancelled,
          _ => AgendaDetailState.scheduled,
        };

  final when = _when(
    entry,
    form,
    exception,
    state: status,
    occurrence: occurrence,
    now: now,
  );

  if (block) {
    final reason = form.reason ?? AgendaBlockReason.other;
    final note = form.blockNote.trim();
    return AgendaDetailViewData(
      state: state,
      title: (exception?.newTitle ?? entry.title).trim().isEmpty
          ? reason.title
          : (exception?.newTitle ?? entry.title).trim(),
      heroIcon: _blockIcon(reason),
      status: const AppStatusPresentation(
        label: 'Indisponível',
        color: AppStatusColor.neutral,
      ),
      showSourceBadge: false,
      when: when,
      valueNotes: note.isEmpty
          ? null
          : AgendaDetailValueNotesViewData(sectionTitle: 'Notas', notes: note),
      unavailableInfo:
          'Só aparece na tua agenda: os pedidos novos continuam a chegar.',
      submitting: submitting,
    );
  }

  final serviceName = serviceTypes
      .where((t) => t.id == entry.serviceTypeId)
      .firstOrNull
      ?.name;
  final title = form.title.trim().isEmpty
      ? (serviceName ?? 'Trabalho')
      : form.title.trim();

  final name = (entry.personName ?? '').trim();
  final phone = (entry.personPhone ?? '').trim();
  final address = (entry.locationLabel ?? '').trim();
  final hasCoords = entry.locationLat != null && entry.locationLng != null;
  final amount = entry.amount;
  final notes = form.notes.trim();

  final String? meta = statusAt == null
      ? null
      : switch (state) {
          AgendaDetailState.done =>
            'Marcado como feito a ${_instant(statusAt, now)}',
          AgendaDetailState.cancelled =>
            'Cancelado a ${_instant(statusAt, now)}',
          _ => null,
        };

  return AgendaDetailViewData(
    state: state,
    title: title,
    heroIcon: entry.serviceTypeId == null
        ? Icons.edit_note_rounded
        : serviceTypeIconFor(serviceTypes, entry.serviceTypeId),
    status: switch (state) {
      AgendaDetailState.done => const AppStatusPresentation(
        label: 'Feito',
        color: AppStatusColor.success,
      ),
      AgendaDetailState.cancelled => const AppStatusPresentation(
        label: 'Cancelado',
        color: AppStatusColor.cancelled,
      ),
      _ => const AppStatusPresentation(
        label: 'Marcado',
        color: AppStatusColor.success,
      ),
    },
    showSourceBadge: true,
    metaLabel: meta,
    overlap: state == AgendaDetailState.scheduled && entries != null
        ? _overlap(
            form,
            entries,
            entryId: entry.id,
            serviceTypes: serviceTypes,
            now: now,
          )
        : null,
    when: when,
    person: name.isEmpty && phone.isEmpty
        ? null
        : AgendaDetailPersonViewData(
            name: name.isEmpty ? phone : name,
            hasWhatsApp: phone.isNotEmpty,
          ),
    place: address.isEmpty && !hasCoords
        ? null
        : AgendaDetailPlaceViewData(
            address: address.isEmpty ? 'Ponto no mapa' : address,
            canOpenMap: true,
          ),
    valueNotes: amount == null && notes.isEmpty
        ? null
        : AgendaDetailValueNotesViewData(
            sectionTitle: amount != null && notes.isNotEmpty
                ? 'Valor e notas'
                : amount != null
                ? 'Valor'
                : 'Notas',
            value: amount == null ? null : '${_euros(amount)} combinado',
            notes: notes.isEmpty ? null : notes,
          ),
    primary: switch (state) {
      AgendaDetailState.done => const AgendaDetailPrimaryViewData(
        kind: AgendaDetailPrimary.undoDone,
        label: 'Afinal não foi feito',
        icon: Icons.undo_rounded,
      ),
      AgendaDetailState.cancelled => const AgendaDetailPrimaryViewData(
        kind: AgendaDetailPrimary.restore,
        label: 'Repor como marcado',
        icon: Icons.event_available_outlined,
      ),
      _ => const AgendaDetailPrimaryViewData(
        kind: AgendaDetailPrimary.markDone,
        label: 'Marcar como feito',
        icon: Icons.check_rounded,
      ),
    },
    showCancel: state == AgendaDetailState.scheduled,
    submitting: submitting,
  );
}

/// Ação que leva à folha "Este trabalho repete-se" (D3).
enum AgendaDetailScopeAction { delete, cancel }

/// Folha D3: um toque numa opção faz logo a ação. A pergunta muda com
/// ela.
AgendaScopeViewData buildAgendaDetailScope({
  required CalendarEntry entry,
  required DateTime occurrence,
  required AgendaDetailScopeAction action,
  required DateTime now,
}) {
  final block = entry.kind == CalendarEntryKind.block;
  final label = agendaRecurrenceLabel(entry.recurrence, entry.startsOn) ?? '';
  final from = agendaShortDate(occurrence, now: now);
  final until = entry.recurrenceUntil;
  final verb = action == AgendaDetailScopeAction.delete ? 'Apagar' : 'Cancelar';
  return AgendaScopeViewData(
    title: block
        ? 'Esta indisponibilidade repete-se'
        : 'Este trabalho repete-se',
    summary: '$verb em que dias?',
    actionLabel: 'Cancelar',
    options: [
      AgendaChoiceViewData(
        id: AgendaSeriesScope.thisDay,
        label: 'Só este dia',
        icon: Icons.today_outlined,
        subtitle:
            '${agendaWeekdayName(occurrence)}, $from. Os outros ficam iguais.',
        selected: true,
      ),
      if (occurrence.isAfter(entry.startsOn))
        AgendaChoiceViewData(
          id: AgendaSeriesScope.following,
          label: 'Este e os seguintes',
          icon: Icons.east_rounded,
          subtitle: until == null
              ? 'De $from em diante. Os anteriores ficam.'
              : 'De $from até ${agendaShortDate(until, now: now)}. '
                    'Os anteriores ficam.',
          selected: false,
        ),
      AgendaChoiceViewData(
        id: AgendaSeriesScope.all,
        label: 'Todos',
        icon: Icons.event_repeat_outlined,
        subtitle: entry.recurrence == AgendaRecurrence.weekly
            ? '$label, do início ao fim.'
            : 'Toda a série, do início ao fim.',
        selected: false,
      ),
    ],
  );
}

/// Que dias leva a ação, para o texto das confirmações.
String _which(
  CalendarEntry entry,
  AgendaEntryForm form,
  DateTime occurrence,
  AgendaSeriesScope? scope,
  DateTime now,
) {
  if (!entry.repeats || scope == AgendaSeriesScope.thisDay) {
    return form.spanDays > 0
        ? _span(form.date, form.lastDay, now)
        : _weekdayDate(form.date, now);
  }
  if (scope == AgendaSeriesScope.following &&
      occurrence.isAfter(entry.startsOn)) {
    return 'de ${agendaShortDate(occurrence, now: now)} em diante';
  }
  return 'todos os dias';
}

/// Diálogo de apagar (D6), com os dias já escolhidos na folha.
AgendaDeleteConfirmData agendaDeleteConfirm({
  required CalendarEntry entry,
  required CalendarException? exception,
  required DateTime occurrence,
  required AgendaSeriesScope? scope,
  required DateTime now,
}) {
  final detail = buildAgendaEntryDetail(
    entry: entry,
    exception: exception,
    occurrence: occurrence,
    entries: null,
    serviceTypes: const [],
    now: now,
  );
  final form = AgendaEntryForm.fromEntry(
    entry,
    occurrenceDate: occurrence,
    exception: exception,
  );
  final name = (entry.personName ?? '').trim();
  return AgendaDeleteConfirmData(
    title: 'Apagar da agenda?',
    message:
        '"${detail.title}", ${_which(entry, form, occurrence, scope, now)}, '
        'sai da agenda.${name.isEmpty ? '' : ' $name não recebe nenhum aviso.'}',
  );
}

/// Confirmação de cancelar: fica na agenda, riscado.
AgendaDeleteConfirmData agendaCancelConfirm({
  required CalendarEntry entry,
  required CalendarException? exception,
  required DateTime occurrence,
  required AgendaSeriesScope? scope,
  required DateTime now,
}) {
  final detail = buildAgendaEntryDetail(
    entry: entry,
    exception: exception,
    occurrence: occurrence,
    entries: null,
    serviceTypes: const [],
    now: now,
  );
  final form = AgendaEntryForm.fromEntry(
    entry,
    occurrenceDate: occurrence,
    exception: exception,
  );
  final name = (entry.personName ?? '').trim();
  return AgendaDeleteConfirmData(
    title: 'Cancelar este trabalho?',
    message:
        '"${detail.title}", ${_which(entry, form, occurrence, scope, now)}, '
        'fica na agenda riscado e podes repô-lo depois.'
        '${name.isEmpty ? '' : ' $name não recebe nenhum aviso.'}',
  );
}
