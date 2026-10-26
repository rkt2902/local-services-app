import 'agenda_entry_model.dart';

/// Uma linha de `worker_calendar_entries` (0064): trabalho fora da app
/// (`job`) ou indisponibilidade (`block`), com a série inteira. É o que o
/// formulário "Adicionar à agenda" lê e escreve; a Agenda lê por
/// `get_worker_agenda`, já desdobrada em dias.
enum CalendarEntryKind {
  job('job'),
  block('block');

  const CalendarEntryKind(this.value);

  final String value;

  static CalendarEntryKind fromValue(String? value) =>
      value == 'block' ? CalendarEntryKind.block : CalendarEntryKind.job;
}

class CalendarEntry {
  const CalendarEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.startsOn,
    this.serviceTypeId,
    this.personName,
    this.personPhone,
    this.locationLabel,
    this.locationLat,
    this.locationLng,
    this.startMinutes,
    this.durationMinutes,
    this.endsOn,
    this.recurrence = AgendaRecurrence.none,
    this.recurrenceUntil,
    this.amount,
    this.notes,
    this.status = 'scheduled',
  });

  factory CalendarEntry.fromJson(Map<String, dynamic> json) => CalendarEntry(
    id: json['id'] as String,
    kind: CalendarEntryKind.fromValue(json['kind'] as String?),
    title: json['title'] as String? ?? '',
    serviceTypeId: json['service_type_id'] as String?,
    personName: json['person_name'] as String?,
    personPhone: json['person_phone'] as String?,
    locationLabel: json['location_label'] as String?,
    locationLat: (json['location_lat'] as num?)?.toDouble(),
    locationLng: (json['location_lng'] as num?)?.toDouble(),
    startsOn: DateTime.parse(json['starts_on'] as String),
    startMinutes: parseTimeMinutes(json['start_time'] as String?),
    durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
    endsOn: _date(json['ends_on']),
    recurrence: AgendaRecurrence.fromValue(json['recurrence'] as String?),
    recurrenceUntil: _date(json['recurrence_until']),
    amount: (json['amount'] as num?)?.toDouble(),
    notes: json['notes'] as String?,
    status: json['status'] as String? ?? 'scheduled',
  );

  final String id;
  final CalendarEntryKind kind;
  final String title;
  final String? serviceTypeId;
  final String? personName;
  final String? personPhone;
  final String? locationLabel;
  final double? locationLat;
  final double? locationLng;

  /// Primeiro dia da série (ou o único).
  final DateTime startsOn;

  /// Nulo = dia todo.
  final int? startMinutes;
  final int? durationMinutes;

  /// Último dia de um trabalho de vários dias; nulo num só dia.
  final DateTime? endsOn;
  final AgendaRecurrence recurrence;
  final DateTime? recurrenceUntil;
  final double? amount;
  final String? notes;
  final String status;

  bool get repeats => recurrence != AgendaRecurrence.none;

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}

/// "Só este dia" de uma série (`worker_calendar_exceptions`). Só guarda o
/// que a 0064 sabe mudar num dia: data, hora, duração, título e notas.
class CalendarException {
  const CalendarException({
    required this.occurrenceDate,
    required this.action,
    this.newDate,
    this.newStartMinutes,
    this.newAllDay = false,
    this.newDurationMinutes,
    this.newTitle,
    this.newNotes,
  });

  factory CalendarException.fromJson(Map<String, dynamic> json) =>
      CalendarException(
        occurrenceDate: DateTime.parse(json['occurrence_date'] as String),
        action: json['action'] as String,
        newDate: json['new_date'] == null
            ? null
            : DateTime.parse(json['new_date'] as String),
        newStartMinutes: parseTimeMinutes(json['new_time'] as String?),
        newAllDay: json['new_all_day'] as bool? ?? false,
        newDurationMinutes: (json['new_duration_minutes'] as num?)?.toInt(),
        newTitle: json['new_title'] as String?,
        newNotes: json['new_notes'] as String?,
      );

  final DateTime occurrenceDate;

  /// `cancelled`, `moved`, `changed` ou `done`.
  final String action;
  final DateTime? newDate;
  final int? newStartMinutes;
  final bool newAllDay;
  final int? newDurationMinutes;
  final String? newTitle;
  final String? newNotes;

  bool get changesFields => action == 'moved' || action == 'changed';
}
