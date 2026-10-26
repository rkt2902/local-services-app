import '../../../core/utils/phone_utils.dart';
import '../data/agenda_calendar_entry.dart';
import '../data/agenda_entry_model.dart';
import 'agenda_conflicts.dart';

/// Estado do formulário "Adicionar à agenda" (design A8D): trabalho fora da
/// app ou indisponível. Lógica pura: valida, diz o que coincide e monta as
/// linhas para `worker_calendar_entries` e `worker_calendar_exceptions`
/// (0064). O ecrã só guarda uma instância e troca-a a cada mudança.
enum AgendaFormType { work, unavailable }

/// Motivo de uma indisponibilidade. Fica no `title` da linha `block` (a
/// 0064 não tem coluna de motivo), por isso "Outro" grava "Indisponível".
enum AgendaBlockReason {
  vacation('Férias'),
  dayOff('Folga'),
  appointment('Consulta'),
  other('Indisponível');

  const AgendaBlockReason(this.title);

  final String title;

  static AgendaBlockReason fromTitle(String title) => values.firstWhere(
    (r) => r.title.toLowerCase() == title.trim().toLowerCase(),
    orElse: () => AgendaBlockReason.other,
  );
}

/// Onde guardar a mudança numa série (F7) ou o que apagar.
enum AgendaSeriesScope { thisDay, following, all }

abstract final class AgendaFormLimits {
  static const titleMax = 80;
  static const personMax = 80;
  static const locationMax = 160;
  static const notesMax = 500;
  static const minDuration = 15;
  static const maxDuration = 24 * 60;

  /// Uma série não repete mais do que 7 dias seguidos (0064,
  /// `worker_calendar_entries_span_check`).
  static const maxRepeatingSpanDays = 6;

  static const defaultStart = 9 * 60;
  static const defaultDuration = 60;
  static const defaultBlockEnd = 13 * 60;
}

const _keep = Object();

class AgendaEntryForm {
  const AgendaEntryForm({
    required this.date,
    this.type = AgendaFormType.work,
    this.title = '',
    this.serviceTypeId,
    this.personName = '',
    this.phone = '',
    this.location = '',
    this.locationLat,
    this.locationLng,
    this.endDate,
    this.allDay = false,
    this.startMinutes = AgendaFormLimits.defaultStart,
    this.durationMinutes = AgendaFormLimits.defaultDuration,
    this.multiDay = false,
    this.endMinutes = AgendaFormLimits.defaultBlockEnd,
    this.recurrence = AgendaRecurrence.none,
    this.recurrenceUntil,
    this.amount = '',
    this.notes = '',
    this.reason,
    this.blockNote = '',
  });

  /// Novo, no dia [date]. Indisponível começa no dia todo.
  factory AgendaEntryForm.create(
    DateTime date, {
    AgendaFormType type = AgendaFormType.work,
  }) => AgendaEntryForm(
    date: _dateOnly(date),
    type: type,
    allDay: type == AgendaFormType.unavailable,
  );

  /// Editar a ocorrência de [occurrenceDate] (o `series_date` da Agenda)
  /// de [entry], com a exceção desse dia por cima, se houver.
  factory AgendaEntryForm.fromEntry(
    CalendarEntry entry, {
    DateTime? occurrenceDate,
    CalendarException? exception,
  }) {
    final changed = exception != null && exception.changesFields;
    final date = _dateOnly(
      (changed ? exception.newDate : null) ?? occurrenceDate ?? entry.startsOn,
    );
    final span = entry.endsOn == null
        ? 0
        : _dateOnly(entry.endsOn!).difference(_dateOnly(entry.startsOn)).inDays;
    final start = changed
        ? (exception.newAllDay
              ? null
              : exception.newStartMinutes ?? entry.startMinutes)
        : entry.startMinutes;
    final duration =
        (changed ? exception.newDurationMinutes : null) ??
        entry.durationMinutes;
    final title = (changed ? exception.newTitle : null) ?? entry.title;
    final notes = (changed ? exception.newNotes : null) ?? entry.notes ?? '';
    final block = entry.kind == CalendarEntryKind.block;
    final startOrDefault = start ?? AgendaFormLimits.defaultStart;

    return AgendaEntryForm(
      type: block ? AgendaFormType.unavailable : AgendaFormType.work,
      date: date,
      endDate: span > 0 ? date.add(Duration(days: span)) : null,
      multiDay: !block && span > 0,
      title: block ? '' : title,
      reason: block ? AgendaBlockReason.fromTitle(title) : null,
      serviceTypeId: entry.serviceTypeId,
      personName: entry.personName ?? '',
      phone: entry.personPhone ?? '',
      location: entry.locationLabel ?? '',
      locationLat: entry.locationLat,
      locationLng: entry.locationLng,
      allDay: start == null,
      startMinutes: startOrDefault,
      durationMinutes: duration ?? AgendaFormLimits.defaultDuration,
      endMinutes: block
          ? (startOrDefault + (duration ?? AgendaFormLimits.defaultDuration))
                .clamp(0, AgendaFormLimits.maxDuration)
          : AgendaFormLimits.defaultBlockEnd,
      recurrence: entry.recurrence,
      recurrenceUntil: entry.recurrenceUntil,
      amount: entry.amount == null ? '' : _amountText(entry.amount!),
      notes: block ? '' : notes,
      blockNote: block ? notes : '',
    );
  }

  final AgendaFormType type;
  final DateTime date;

  // Trabalho
  final String title;
  final String? serviceTypeId;
  final String personName;
  final String phone;
  final String location;

  /// Só quando a morada veio de uma sugestão; escrever à mão limpa-as.
  final double? locationLat;
  final double? locationLng;
  final int durationMinutes;
  final bool multiDay;
  final String amount;
  final String notes;

  // Comum
  /// Último dia: "Até" de vários dias ou de uma indisponibilidade.
  final DateTime? endDate;
  final bool allDay;
  final int startMinutes;
  final AgendaRecurrence recurrence;
  final DateTime? recurrenceUntil;

  // Indisponível
  final AgendaBlockReason? reason;
  final String blockNote;

  /// Hora de fim de uma indisponibilidade com horas.
  final int endMinutes;

  bool get isWork => type == AgendaFormType.work;

  /// Último dia ocupado (o próprio [date] num só dia).
  DateTime get lastDay {
    final end = endDate;
    final usesEnd = isWork ? multiDay : true;
    if (!usesEnd || end == null || end.isBefore(date)) return date;
    return end;
  }

  int get spanDays => lastDay.difference(date).inDays;

  AgendaEntryForm copyWith({
    AgendaFormType? type,
    DateTime? date,
    String? title,
    Object? serviceTypeId = _keep,
    String? personName,
    String? phone,
    String? location,
    Object? locationLat = _keep,
    Object? locationLng = _keep,
    Object? endDate = _keep,
    bool? allDay,
    int? startMinutes,
    int? durationMinutes,
    bool? multiDay,
    int? endMinutes,
    AgendaRecurrence? recurrence,
    Object? recurrenceUntil = _keep,
    String? amount,
    String? notes,
    Object? reason = _keep,
    String? blockNote,
  }) => AgendaEntryForm(
    type: type ?? this.type,
    date: date == null ? this.date : _dateOnly(date),
    title: title ?? this.title,
    serviceTypeId: identical(serviceTypeId, _keep)
        ? this.serviceTypeId
        : serviceTypeId as String?,
    personName: personName ?? this.personName,
    phone: phone ?? this.phone,
    location: location ?? this.location,
    locationLat: identical(locationLat, _keep)
        ? this.locationLat
        : locationLat as double?,
    locationLng: identical(locationLng, _keep)
        ? this.locationLng
        : locationLng as double?,
    endDate: identical(endDate, _keep) ? this.endDate : endDate as DateTime?,
    allDay: allDay ?? this.allDay,
    startMinutes: startMinutes ?? this.startMinutes,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    multiDay: multiDay ?? this.multiDay,
    endMinutes: endMinutes ?? this.endMinutes,
    recurrence: recurrence ?? this.recurrence,
    recurrenceUntil: identical(recurrenceUntil, _keep)
        ? this.recurrenceUntil
        : recurrenceUntil as DateTime?,
    amount: amount ?? this.amount,
    notes: notes ?? this.notes,
    reason: identical(reason, _keep)
        ? this.reason
        : reason as AgendaBlockReason?,
    blockNote: blockNote ?? this.blockNote,
  );

  /// Trocar entre Trabalho e Indisponível guarda data e horas (nota 5).
  AgendaEntryForm switchType(AgendaFormType next) {
    if (next == type) return this;
    if (next == AgendaFormType.unavailable) {
      return copyWith(
        type: next,
        endMinutes: (startMinutes + durationMinutes).clamp(
          startMinutes + AgendaFormLimits.minDuration,
          AgendaFormLimits.maxDuration,
        ),
      );
    }
    final length = endMinutes - startMinutes;
    return copyWith(
      type: next,
      durationMinutes: length >= AgendaFormLimits.minDuration
          ? length
          : durationMinutes,
      multiDay: endDate != null && endDate!.isAfter(date),
    );
  }

  /// Escolher outra data de início arrasta o "Até" (vários dias,
  /// indisponível) e a repetição, para não ficarem antes.
  AgendaEntryForm withDate(DateTime value) {
    final next = _dateOnly(value);
    final shift = next.difference(date);
    final end = endDate;
    final until = recurrenceUntil;
    return copyWith(
      date: next,
      endDate: end?.add(shift),
      recurrenceUntil: until == null || !until.isBefore(next) ? until : next,
    );
  }

  /// Porque não dá para guardar, ou nulo. O texto aparece por cima do botão.
  String? get blocker {
    if (isWork && title.trim().isEmpty) {
      return 'Escreve um título para poder guardar.';
    }
    if (!isWork && reason == null) {
      return 'Escolhe o motivo para poder guardar.';
    }
    if (isWork && phone.trim().isNotEmpty && whatsAppNumber(phone) == null) {
      return invalidPhoneMessage;
    }
    if (isWork && amount.trim().isNotEmpty && amountValue == null) {
      return 'Valor inválido. Ex.: 25 ou 25,50.';
    }
    final end = endDate;
    if ((isWork ? multiDay : true) && end != null && end.isBefore(date)) {
      return 'O último dia tem de ser depois do primeiro.';
    }
    if (!isWork && !allDay && endMinutes <= startMinutes) {
      return 'A hora de fim tem de ser depois da de início.';
    }
    if (recurrence != AgendaRecurrence.none &&
        spanDays > AgendaFormLimits.maxRepeatingSpanDays) {
      return 'Só dá para repetir o que dura até 7 dias seguidos.';
    }
    final until = recurrenceUntil;
    if (recurrence != AgendaRecurrence.none &&
        until != null &&
        until.isBefore(date)) {
      return 'A repetição tem de acabar depois do primeiro dia.';
    }
    return null;
  }

  bool get canSave => blocker == null;

  /// "25" ou "25,50" → 25.5. Nulo se vazio ou inválido.
  double? get amountValue {
    final text = amount.trim().replaceAll('€', '').replaceAll(' ', '');
    if (text.isEmpty) return null;
    final value = double.tryParse(text.replaceAll(',', '.'));
    return value == null || value < 0 ? null : value;
  }

  /// Hora de início, nula no dia todo.
  int? get effectiveStart => allDay ? null : startMinutes;

  /// Duração gravada: nula no dia todo e em vários dias (ocupam o dia).
  int? get effectiveDuration {
    if (allDay) return null;
    if (isWork) return multiDay && spanDays > 0 ? null : durationMinutes;
    return endMinutes - startMinutes;
  }

  /// Linha para `worker_calendar_entries`. Sem `worker_id` (DEFAULT
  /// `auth.uid()`) nem `status`. [startsOn] muda o primeiro dia da série
  /// (editar "Todos" a partir de outra ocorrência); o "Até" anda com ele.
  Map<String, dynamic> toRow({DateTime? startsOn}) {
    final first = startsOn == null ? date : _dateOnly(startsOn);
    final span = spanDays;
    final start = effectiveStart;
    final phoneNumber = whatsAppNumber(phone);
    final place = _trimTo(location, AgendaFormLimits.locationMax);
    return {
      'kind': isWork
          ? CalendarEntryKind.job.value
          : CalendarEntryKind.block.value,
      'title': isWork
          ? _trimTo(title, AgendaFormLimits.titleMax)
          : (reason ?? AgendaBlockReason.other).title,
      'service_type_id': isWork ? serviceTypeId : null,
      'person_name': isWork
          ? _trimTo(personName, AgendaFormLimits.personMax)
          : null,
      'person_phone': isWork && phoneNumber != null ? '+$phoneNumber' : null,
      'location_label': isWork ? place : null,
      'location_lat': isWork && place != null ? locationLat : null,
      'location_lng': isWork && place != null ? locationLng : null,
      'starts_on': _dateText(first),
      'start_time': start == null ? null : '${formatMinutes(start)}:00',
      'duration_minutes': effectiveDuration,
      'ends_on': span > 0 ? _dateText(first.add(Duration(days: span))) : null,
      'recurrence': recurrence.value,
      'recurrence_until': recurrence == AgendaRecurrence.none
          ? null
          : (recurrenceUntil == null ? null : _dateText(recurrenceUntil!)),
      'amount': isWork ? amountValue : null,
      'notes': _trimTo(isWork ? notes : blockNote, AgendaFormLimits.notesMax),
    };
  }

  /// "Só este dia": o que a exceção guarda (0064). Data diferente de
  /// [occurrenceDate] = `moved`.
  Map<String, dynamic> toExceptionRow(DateTime occurrenceDate) {
    final start = effectiveStart;
    final moved = !_sameDay(date, occurrenceDate);
    return {
      'action': moved ? 'moved' : 'changed',
      'new_date': moved ? _dateText(date) : null,
      'new_time': start == null ? null : '${formatMinutes(start)}:00',
      'new_all_day': allDay,
      'new_duration_minutes': effectiveDuration,
      'new_title': isWork
          ? _trimTo(title, AgendaFormLimits.titleMax)
          : (reason ?? AgendaBlockReason.other).title,
      'new_notes': _trimTo(
        isWork ? notes : blockNote,
        AgendaFormLimits.notesMax,
      ),
    };
  }

  /// Exceção que tira só um dia da série.
  static Map<String, dynamic> cancelledExceptionRow() => {
    'action': 'cancelled',
    'new_date': null,
    'new_time': null,
    'new_all_day': false,
    'new_duration_minutes': null,
    'new_title': null,
    'new_notes': null,
  };

  /// Só mudou o que uma exceção sabe guardar (data, horas, título, notas)?
  /// Se não, "Só este dia" não chega e a escolha fica desligada.
  bool onlyOccurrenceFieldsChanged(AgendaEntryForm original) =>
      type == original.type &&
      serviceTypeId == original.serviceTypeId &&
      personName.trim() == original.personName.trim() &&
      phone.trim() == original.phone.trim() &&
      location.trim() == original.location.trim() &&
      spanDays == original.spanDays &&
      recurrence == original.recurrence &&
      _sameDayOrNull(recurrenceUntil, original.recurrenceUntil) &&
      amountValue == original.amountValue;

  /// O que coincide com este trabalho, do mais grave para o mais leve.
  /// Vários dias contam como dia todo em cada dia (no máximo 7). Só
  /// trabalhos: uma indisponibilidade usa [entriesInRange].
  List<AgendaConflict> conflicts(
    List<AgendaEntry> entries, {
    String? ignoreSourceId,
  }) {
    if (!isWork) return const [];
    final span = spanDays.clamp(0, AgendaFormLimits.maxRepeatingSpanDays);
    final result = <AgendaConflict>[];
    for (var i = 0; i <= span; i++) {
      final day = date.add(Duration(days: i));
      final slot = AgendaSlot(
        date: day,
        startMinutes: span > 0 ? null : effectiveStart,
        durationMinutes: span > 0 ? null : effectiveDuration,
        wholeDay: span > 0,
        ignoreSourceId: ignoreSourceId,
      );
      result.addAll(
        conflictsForSlot(slot, entries, slotKind: AgendaEntryKind.external),
      );
    }
    result.sort((a, b) => a.level.index.compareTo(b.level.index));
    return result;
  }

  /// Trabalhos e propostas abertos nos dias de uma indisponibilidade
  /// (ficam na Agenda; F6 só avisa).
  List<AgendaEntry> entriesInRange(
    List<AgendaEntry> entries, {
    String? ignoreSourceId,
  }) => [
    for (final e in entries)
      if (e.kind != AgendaEntryKind.block &&
          !e.isClosed &&
          e.sourceId != ignoreSourceId &&
          !e.date.isBefore(date) &&
          !e.date.isAfter(lastDay))
        e,
  ];
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _sameDayOrNull(DateTime? a, DateTime? b) =>
    (a == null && b == null) || (a != null && b != null && _sameDay(a, b));

String _dateText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String? _trimTo(String value, int max) {
  final text = value.trim();
  if (text.isEmpty) return null;
  return text.length <= max ? text : text.substring(0, max);
}

/// 25.0 → "25", 25.5 → "25,50".
String _amountText(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(2).replaceAll('.', ',');
