import 'package:flutter/material.dart';

import '../../../core/services/geocoding_service.dart';
import '../../../core/widgets/service_icon.dart';
import '../../worker/data/service_type_model.dart';
import '../application/agenda_conflicts.dart';
import '../application/agenda_entry_form.dart';
import '../data/agenda_entry_model.dart';
import 'agenda_day_presenter.dart';
import 'agenda_entry_editor_view_data.dart';

/// Monta o formulário "Adicionar à agenda" (A8D) a partir do estado
/// ([AgendaEntryForm]) e da leitura da Agenda: textos, escolhas, nota de
/// sobreposição, confirmação forte e folha da série.

/// Durações fixas dos chips (o resto vai por "Outra").
const agendaDurationPresets = [60, 120, 240];

/// 60 → "1 h", 90 → "1 h 30", 45 → "45 min".
String agendaDurationLabel(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h ${m.toString().padLeft(2, '0')}';
}

/// "Terça, 10 nov".
String _dayLabel(DateTime day, DateTime now) =>
    '${agendaWeekdayName(day)}, ${agendaShortDate(day, now: now)}';

/// Zona curta: "Rua A 1, Cascais" → "Cascais".
String? _area(String? label) {
  final text = label?.trim() ?? '';
  if (text.isEmpty) return null;
  return text.split(',').last.trim();
}

String _range(int start, int end) =>
    '${formatMinutes(start)} a ${formatMinutes(end.clamp(0, 24 * 60))}';

AgendaRecurrenceViewData _recurrence(AgendaEntryForm form, DateTime now) {
  final until = form.recurrenceUntil;
  final repeats = form.recurrence != AgendaRecurrence.none;
  String? summary;
  if (repeats) {
    final base = agendaRecurrenceLabel(form.recurrence, form.date)!;
    final start = form.effectiveStart;
    final at = start == null ? '' : ' às ${formatMinutes(start)}';
    final end = until == null
        ? ', sem fim'
        : ', até ${agendaShortDate(until, now: now)}';
    summary = '$base$at$end';
  }
  return AgendaRecurrenceViewData(
    choices: [
      for (final (r, label) in const [
        (AgendaRecurrence.none, 'Não repete'),
        (AgendaRecurrence.weekly, 'Todas as semanas'),
        (AgendaRecurrence.biweekly, 'De 15 em 15 dias'),
        (AgendaRecurrence.monthly, 'Todos os meses'),
      ])
        AgendaChoiceViewData(
          id: r.value,
          label: label,
          selected: form.recurrence == r,
        ),
    ],
    showUntil: repeats,
    untilLabel: until == null ? 'Sem fim' : _dayLabel(until, now),
    noEnd: until == null,
    summary: summary,
  );
}

List<AgendaChoiceViewData<AgendaDurationId>> _durations(AgendaEntryForm form) {
  final multi = form.multiDay;
  final allDay = form.allDay && !multi;
  final timed = !multi && !allDay;
  final custom = timed && !agendaDurationPresets.contains(form.durationMinutes);
  return [
    for (final minutes in agendaDurationPresets)
      AgendaChoiceViewData(
        id: AgendaDurationId(AgendaDurationOption.preset, minutes),
        label: agendaDurationLabel(minutes),
        selected: timed && form.durationMinutes == minutes,
      ),
    AgendaChoiceViewData(
      id: const AgendaDurationId(AgendaDurationOption.allDay),
      label: 'Dia todo',
      selected: allDay,
    ),
    AgendaChoiceViewData(
      id: const AgendaDurationId(AgendaDurationOption.multiDay),
      label: 'Vários dias',
      selected: multi,
    ),
    AgendaChoiceViewData(
      id: const AgendaDurationId(AgendaDurationOption.custom),
      label: custom ? agendaDurationLabel(form.durationMinutes) : 'Outra',
      selected: custom,
    ),
  ];
}

String? _timeSummary(AgendaEntryForm form, DateTime now) {
  if (form.multiDay) {
    if (form.spanDays == 0) return 'Escolhe o último dia.';
    final from = _dayLabel(form.date, now);
    final to = _dayLabel(form.lastDay, now).toLowerCase();
    final start = form.effectiveStart;
    return start == null
        ? '$from a $to, dia todo'
        : '$from a $to, a partir das ${formatMinutes(start)}';
  }
  if (form.allDay) return 'Dia todo, sem hora marcada';
  final start = form.startMinutes;
  final end = start + form.durationMinutes;
  return end >= 24 * 60
      ? 'Das ${formatMinutes(start)} até ao fim do dia'
      : 'Das ${formatMinutes(start)} às ${formatMinutes(end)}';
}

AgendaInlineWarningViewData? _workWarning(
  AgendaEntryForm form,
  List<AgendaEntry> entries, {
  required String? ignoreSourceId,
  required List<ServiceType> serviceTypes,
  required DateTime now,
}) {
  final conflicts = form.conflicts(entries, ignoreSourceId: ignoreSourceId);
  if (conflicts.isEmpty) return null;
  final c = conflicts.first;
  final other = c.other;
  final name = agendaEntryViewData(
    other,
    now: now,
    isToday: false,
    current: false,
    serviceTypes: serviceTypes,
  ).title;
  final area = _area(other.locationLabel);
  final where = area == null ? '' : ', $area';
  final theirs = occupiedMinutes(other);
  final theirsWholeDay =
      theirs != null && theirs.$1 == 0 && theirs.$2 >= 24 * 60;
  final day = form.spanDays > 0 && other.date != form.date
      ? '${agendaWeekdayName(other.date)}: '
      : '';

  String message;
  final tentative = c.level == AgendaConflictLevel.tentative;
  switch (c.reason) {
    case AgendaConflictReason.overlap:
      message = tentative
          ? 'Já enviaste uma proposta para esta hora: $name$where, '
                '${_range(theirs!.$1, theirs.$2)}.'
          : 'Coincide com $name$where, ${_range(theirs!.$1, theirs.$2)}.';
    case AgendaConflictReason.wholeDay:
      if (other.kind == AgendaEntryKind.block) {
        message = 'Estás indisponível neste dia ($name).';
      } else if (tentative) {
        message = 'Já tens uma proposta neste dia: $name$where.';
      } else if (theirsWholeDay || theirs == null) {
        message = 'Já tens $name neste dia$where.';
      } else {
        message =
            'Já tens $name neste dia$where, ${_range(theirs.$1, theirs.$2)}.';
      }
    case AgendaConflictReason.sameDayNoTime:
      message = tentative
          ? 'Já tens uma proposta neste dia: $name$where.'
          : theirs == null
          ? 'Já tens $name neste dia, sem hora marcada.'
          : 'Já tens $name neste dia, ${_range(theirs.$1, theirs.$2)}.';
    case AgendaConflictReason.shortGap:
      final gap = c.gapMinutes ?? 0;
      final mine = form.effectiveStart ?? 0;
      final after = theirs != null && mine >= theirs.$2;
      message = after
          ? 'Só $gap min depois de $name$where.'
          : 'Só $gap min antes de $name$where.';
  }
  final more = conflicts.length - 1;
  if (more > 0) message = '$message E mais $more.';

  return AgendaInlineWarningViewData(
    tone: c.level == AgendaConflictLevel.strong
        ? AgendaWarningTone.waiting
        : AgendaWarningTone.info,
    message: '$day$message',
    actionLabel: 'Ver o dia',
  );
}

AgendaInlineWarningViewData? _blockWarning(
  AgendaEntryForm form,
  List<AgendaEntry> entries, {
  required String? ignoreSourceId,
}) {
  final found = form.entriesInRange(entries, ignoreSourceId: ignoreSourceId);
  if (found.isEmpty) return null;
  // Um trabalho de vários dias conta uma vez.
  final jobs = {
    for (final e in found)
      if (!e.isTentative) '${e.kind.value}:${e.sourceId}:${e.seriesDate}',
  }.length;
  final proposals = {
    for (final e in found)
      if (e.isTentative) '${e.kind.value}:${e.sourceId}',
  }.length;
  final parts = [
    if (jobs > 0) jobs == 1 ? '1 trabalho' : '$jobs trabalhos',
    if (proposals > 0) proposals == 1 ? '1 proposta' : '$proposals propostas',
  ];
  final where = form.spanDays > 0 ? 'nestes dias' : 'neste dia';
  return AgendaInlineWarningViewData(
    tone: AgendaWarningTone.info,
    message:
        'Já tens ${parts.join(' e ')} $where. Ficam na agenda; tu decides '
        'o que mudar.',
  );
}

/// O formulário pronto a mostrar. [entries] nulo = a Agenda ainda está a
/// carregar (sem nota de sobreposição). [ignoreSourceId] é a própria
/// entrada, ao editar.
AgendaEditorViewData buildAgendaEditor({
  required AgendaEntryForm form,
  required bool isEdit,
  required List<AgendaEntry>? entries,
  required List<ServiceType> serviceTypes,
  required DateTime now,
  bool submitting = false,
  String? ignoreSourceId,
  List<AddressSuggestion> suggestions = const [],
  bool suggestionsLoading = false,
}) {
  final service = serviceTypes
      .where((t) => t.id == form.serviceTypeId)
      .firstOrNull;
  final recurrence = _recurrence(form, now);
  final blocker = form.blocker;

  return AgendaEditorViewData(
    title: isEdit ? 'Editar' : 'Adicionar à agenda',
    type: form.type,
    showTypeSelector: !isEdit,
    showDelete: isEdit,
    saveLabel: isEdit
        ? 'Guardar alterações'
        : form.isWork
        ? 'Guardar na agenda'
        : 'Guardar',
    canSave: blocker == null && !submitting,
    submitting: submitting,
    saveHelper: blocker,
    work: AgendaWorkFormViewData(
      serviceLabel: service?.name,
      serviceIcon: service == null ? null : serviceIconFor(service.icon),
      suggestions: suggestions.take(4).toList(),
      suggestionsLoading: suggestionsLoading,
      dateLabel: agendaDayLabel(form.date, now),
      startTimeLabel: formatMinutes(form.startMinutes),
      allDay: form.allDay,
      durationChoices: _durations(form),
      timeSummary: _timeSummary(form, now),
      multiDay: form.multiDay,
      endDateLabel: _dayLabel(form.lastDay, now),
      warning: entries == null || !form.isWork
          ? null
          : _workWarning(
              form,
              entries,
              ignoreSourceId: ignoreSourceId,
              serviceTypes: serviceTypes,
              now: now,
            ),
      recurrence: recurrence,
    ),
    unavailable: AgendaUnavailableFormViewData(
      reasons: [
        for (final (r, label, icon) in const [
          (AgendaBlockReason.vacation, 'Férias', Icons.beach_access_outlined),
          (AgendaBlockReason.dayOff, 'Folga', Icons.weekend_outlined),
          (
            AgendaBlockReason.appointment,
            'Consulta',
            Icons.medical_services_outlined,
          ),
          (AgendaBlockReason.other, 'Outro', Icons.more_horiz_rounded),
        ])
          AgendaChoiceViewData(
            id: r,
            label: label,
            icon: icon,
            selected: form.reason == r,
          ),
      ],
      startDateLabel: _dayLabel(form.date, now),
      endDateLabel: _dayLabel(form.lastDay, now),
      allDay: form.allDay,
      startTimeLabel: formatMinutes(form.startMinutes),
      endTimeLabel: formatMinutes(form.endMinutes),
      recurrence: recurrence,
      info:
          'Só aparece na tua agenda. Os pedidos continuam a aparecer; se '
          'propuseres para estes dias, avisamos-te.',
      warning: entries == null || form.isWork
          ? null
          : _blockWarning(form, entries, ignoreSourceId: ignoreSourceId),
    ),
  );
}

/// Confirmação ao tocar em Guardar (F4): só quando as horas se cruzam com
/// um trabalho marcado (não com propostas). Nulo = guarda logo.
AgendaConflictDialogData? agendaStrongConflict({
  required AgendaEntryForm form,
  required List<AgendaEntry> entries,
  required List<ServiceType> serviceTypes,
  required DateTime now,
  String? ignoreSourceId,
}) {
  final strong = form
      .conflicts(entries, ignoreSourceId: ignoreSourceId)
      .where((c) => c.level == AgendaConflictLevel.strong)
      .firstOrNull;
  if (strong == null) return null;
  final other = strong.other;
  final card = agendaEntryViewData(
    other,
    now: now,
    isToday: false,
    current: false,
    serviceTypes: serviceTypes,
  );

  final String title;
  final String summary;
  if (strong.reason == AgendaConflictReason.overlap) {
    final start = form.startMinutes;
    final end = (start + form.durationMinutes).clamp(0, 24 * 60);
    final overlap = (strong.overlapEnd ?? 0) - (strong.overlapStart ?? 0);
    title = 'Já tens um trabalho a esta hora';
    summary =
        'O novo fica das ${formatMinutes(start)} às ${formatMinutes(end)}. '
        'Cruzam-se ${agendaDurationLabel(overlap)}.';
  } else {
    title = other.kind == AgendaEntryKind.block
        ? 'Estás indisponível neste dia'
        : 'Já tens um trabalho neste dia';
    summary = 'Podes guardar na mesma; o dia fica marcado a âmbar na agenda.';
  }
  return AgendaConflictDialogData(
    title: title,
    entryStart: card.startLabel,
    entryEnd: card.endLabel,
    entryTitle: card.title,
    entryMeta: card.subtitle,
    summary: summary,
  );
}

/// Folha "Guardar a mudança em…" ou "Apagar…" de uma série (F7). Sem
/// [thisDayAllowed], "Só este dia" fica desligado (mudou o que uma exceção
/// não guarda). "Este e os seguintes" só aparece depois do primeiro dia.
AgendaScopeViewData buildAgendaScope({
  required String entryTitle,
  required AgendaRecurrence recurrence,
  required DateTime seriesStart,
  required DateTime occurrenceDate,
  required DateTime now,
  required bool forDelete,
  DateTime? recurrenceUntil,
  bool thisDayAllowed = true,
  AgendaSeriesScope selected = AgendaSeriesScope.thisDay,
}) {
  final label = agendaRecurrenceLabel(recurrence, seriesStart) ?? '';
  final showFollowing = occurrenceDate.isAfter(seriesStart);
  var chosen = selected;
  if (chosen == AgendaSeriesScope.thisDay && !thisDayAllowed) {
    chosen = AgendaSeriesScope.all;
  }
  if (chosen == AgendaSeriesScope.following && !showFollowing) {
    chosen = AgendaSeriesScope.all;
  }
  final from = agendaShortDate(occurrenceDate, now: now);
  final until = recurrenceUntil;

  return AgendaScopeViewData(
    title: forDelete ? 'Apagar…' : 'Guardar a mudança em…',
    summary: '$entryTitle repete ${label.toLowerCase()}.',
    actionLabel: forDelete ? 'Apagar' : 'Guardar',
    options: [
      AgendaChoiceViewData(
        id: AgendaSeriesScope.thisDay,
        label: 'Só este dia',
        subtitle: thisDayAllowed
            ? _dayLabel(occurrenceDate, now)
            : 'Num só dia dá para mudar data, horas, título e notas.',
        selected: chosen == AgendaSeriesScope.thisDay,
        enabled: thisDayAllowed,
      ),
      if (showFollowing)
        AgendaChoiceViewData(
          id: AgendaSeriesScope.following,
          label: 'Este e os seguintes',
          subtitle: until == null
              ? 'De $from em diante'
              : 'De $from até ${agendaShortDate(until, now: now)}',
          selected: chosen == AgendaSeriesScope.following,
        ),
      AgendaChoiceViewData(
        id: AgendaSeriesScope.all,
        label: 'Todos',
        subtitle: recurrence == AgendaRecurrence.weekly
            ? '$label da série'
            : 'Toda a série',
        selected: chosen == AgendaSeriesScope.all,
      ),
    ],
  );
}
