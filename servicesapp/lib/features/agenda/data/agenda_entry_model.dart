/// Uma linha de `get_worker_agenda` (0064): um dia ocupado por um trabalho,
/// uma proposta, uma entrada de fora da app ou uma indisponibilidade.
/// Um trabalho de 3 dias chega em 3 linhas (`dayIndex` 1..3).
enum AgendaEntryKind {
  /// Sou o responsável.
  appJob('app_job'),

  /// Sou ajudante aceite.
  helperJob('helper_job'),

  /// Proposta pendente com data (tentativa).
  proposal('proposal'),

  /// Nova data pedida numa remarcação por aceitar (tentativa).
  reschedule('reschedule'),

  /// Trabalho fora da app.
  external('external'),

  /// Indisponível (férias, folga).
  block('block');

  const AgendaEntryKind(this.value);

  final String value;

  static AgendaEntryKind fromValue(String value) => values.firstWhere(
    (k) => k.value == value,
    orElse: () => AgendaEntryKind.external,
  );
}

enum AgendaRecurrence {
  none('none'),
  weekly('weekly'),
  biweekly('biweekly'),
  monthly('monthly');

  const AgendaRecurrence(this.value);

  final String value;

  static AgendaRecurrence fromValue(String? value) => values.firstWhere(
    (r) => r.value == value,
    orElse: () => AgendaRecurrence.none,
  );
}

class AgendaEntry {
  const AgendaEntry({
    required this.kind,
    required this.sourceId,
    required this.date,
    required this.seriesDate,
    required this.status,
    this.jobId,
    this.startMinutes,
    this.endMinutes,
    this.dayIndex = 1,
    this.dayCount = 1,
    this.title,
    this.serviceTypeId,
    this.locationLabel,
    this.personName,
    this.personPhone,
    this.isTentative = false,
    this.amountMin,
    this.amountMax,
    this.recurrence = AgendaRecurrence.none,
    this.isException = false,
    this.notes,
  });

  factory AgendaEntry.fromJson(Map<String, dynamic> json) {
    final date = DateTime.parse(json['occurrence_date'] as String);
    return AgendaEntry(
      kind: AgendaEntryKind.fromValue(json['entry_kind'] as String),
      sourceId: json['source_id'] as String,
      jobId: json['job_id'] as String?,
      date: date,
      seriesDate: json['series_date'] == null
          ? date
          : DateTime.parse(json['series_date'] as String),
      startMinutes: parseTimeMinutes(json['start_time'] as String?),
      endMinutes: parseTimeMinutes(json['end_time'] as String?),
      dayIndex: (json['day_index'] as num?)?.toInt() ?? 1,
      dayCount: (json['day_count'] as num?)?.toInt() ?? 1,
      title: json['title'] as String?,
      serviceTypeId: json['service_type_id'] as String?,
      locationLabel: json['location_label'] as String?,
      personName: json['person_name'] as String?,
      personPhone: json['person_phone'] as String?,
      status: json['status'] as String? ?? '',
      isTentative: json['is_tentative'] as bool? ?? false,
      amountMin: (json['amount_min'] as num?)?.toDouble(),
      amountMax: (json['amount_max'] as num?)?.toDouble(),
      recurrence: AgendaRecurrence.fromValue(json['recurrence'] as String?),
      isException: json['is_exception'] as bool? ?? false,
      notes: json['notes'] as String?,
    );
  }

  final AgendaEntryKind kind;

  /// Pedido (app_job, reschedule), candidatura (helper_job), proposta ou
  /// série (external, block).
  final String sourceId;

  /// Pedido para abrir o detalhe; nulo nas entradas de fora da app.
  final String? jobId;

  /// Dia desta linha (só a data, hora de Portugal).
  final DateTime date;

  /// Dia da ocorrência na série (para "Só este dia"); igual a [date] fora
  /// das séries, e o primeiro dia num trabalho de vários dias.
  final DateTime seriesDate;

  /// Minutos desde a meia-noite. Nulo = dia todo ou hora a combinar.
  final int? startMinutes;

  /// Fim estimado; nulo quando não há duração.
  final int? endMinutes;

  final int dayIndex;
  final int dayCount;

  /// Só nas entradas de fora da app; as da app usam o serviço.
  final String? title;
  final String? serviceTypeId;
  final String? locationLabel;
  final String? personName;
  final String? personPhone;

  /// `confirmed`, `in_progress`, `awaiting_confirmation`, `completed`,
  /// `pending`, `scheduled`, `done`.
  final String status;

  final bool isTentative;
  final double? amountMin;
  final double? amountMax;
  final AgendaRecurrence recurrence;

  /// Esta ocorrência foi mudada à parte ("Mudado só este dia").
  final bool isException;
  final String? notes;

  bool get hasTime => startMinutes != null;

  bool get isMultiDay => dayCount > 1;

  /// Já não ocupa tempo: concluído, feito ou cancelado.
  bool get isClosed =>
      status == 'completed' || status == 'done' || status == 'cancelled';
}

/// "09:00:00" ou "09:00" → 540. Nulo ou inválido → nulo.
int? parseTimeMinutes(String? value) {
  if (value == null) return null;
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// 540 → "09:00".
String formatMinutes(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}
