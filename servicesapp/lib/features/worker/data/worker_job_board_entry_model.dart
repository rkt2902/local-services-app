/// Papel do worker autenticado numa entrada do "board" unificado — deriva
/// de estar em `job_proposals` (responsável) ou `help_acceptances`
/// (ajudante). Ver `get_worker_job_board` (migration 0035).
enum WorkerJobBoardRole {
  responsible,
  helper;

  static WorkerJobBoardRole fromValue(String value) => switch (value) {
        'helper' => WorkerJobBoardRole.helper,
        _ => WorkerJobBoardRole.responsible,
      };
}

/// Uma linha do RPC `get_worker_job_board` — uma proposta (responsável) ou
/// uma candidatura de ajuda (ajudante), já filtrada e ordenada
/// server-side pela tab pedida (`pending`/`scheduled`/`completed`).
class WorkerJobBoardEntry {
  final String entryId;
  final WorkerJobBoardRole role;
  final String jobId;
  final String serviceTypeName;

  /// Cliente (papel responsável) ou principal (papel ajudante) — já
  /// resolvido pelo RPC, sem necessidade de fetch adicional no Flutter.
  final String personName;
  final String addressText;
  final DateTime? preferredDate;
  final DateTime? confirmedDate;
  final String? confirmedTime;
  final bool confirmedFlexible;

  /// Só preenchido para role == responsible.
  final double? hourlyRate;
  final double? estimatedHoursMin;
  final double? estimatedHoursMax;

  /// Só preenchido para role == helper.
  final double? agreedRate;

  /// Valor bruto do enum específico do papel — `ProposalStatus` para
  /// responsible, `HelpAcceptanceStatus` para helper. O caller decide qual
  /// enum usar consoante `role`.
  final String status;
  final DateTime createdAt;

  /// Estado do pedido (`job_requests.status`), devolvido desde a 0048.
  /// `null` com a BD antiga: o ecrã usa então só [status].
  final String? jobStatus;

  /// `COUNT(*) OVER()` sobre o filtro da tab — igual em todas as linhas da
  /// mesma página/tab; usado para o badge de contagem e para saber se há
  /// mais páginas, sem precisar de uma query de contagem à parte.
  final int totalCount;

  /// Campos da 0053 para os cartões do design A2. Todos `null` com a BD
  /// antiga: o ecrã cai no nome do serviço, na morada e em [createdAt].
  final String? serviceTypeId;

  /// Só a localidade ("Cascais").
  final String? locationArea;
  final DateTime? markedDoneAt;
  final String? cancelReason;
  final bool cancelledByClient;
  final bool cancelledByMe;

  /// Última alteração do pedido (ou da proposta): data do cartão no
  /// Histórico.
  final DateTime? jobUpdatedAt;

  /// Início do trabalho (0052, devolvido desde a 0053): badge "Em curso".
  final DateTime? startedAt;

  const WorkerJobBoardEntry({
    required this.entryId,
    required this.role,
    required this.jobId,
    required this.serviceTypeName,
    required this.personName,
    required this.addressText,
    this.preferredDate,
    this.confirmedDate,
    this.confirmedTime,
    this.confirmedFlexible = false,
    this.hourlyRate,
    this.estimatedHoursMin,
    this.estimatedHoursMax,
    this.agreedRate,
    required this.status,
    required this.createdAt,
    this.jobStatus,
    this.totalCount = 0,
    this.serviceTypeId,
    this.locationArea,
    this.markedDoneAt,
    this.cancelReason,
    this.cancelledByClient = false,
    this.cancelledByMe = false,
    this.jobUpdatedAt,
    this.startedAt,
  });

  factory WorkerJobBoardEntry.fromJson(Map<String, dynamic> json) =>
      WorkerJobBoardEntry(
        entryId: json['entry_id'] as String,
        role: WorkerJobBoardRole.fromValue(json['role'] as String),
        jobId: json['job_id'] as String,
        serviceTypeName: json['service_type_name'] as String? ?? '—',
        personName: json['person_name'] as String? ?? '',
        addressText: json['address_text'] as String? ?? '',
        preferredDate: json['preferred_date'] != null
            ? DateTime.parse(json['preferred_date'] as String)
            : null,
        confirmedDate: json['confirmed_date'] != null
            ? DateTime.parse(json['confirmed_date'] as String)
            : null,
        confirmedTime: json['confirmed_time'] as String?,
        confirmedFlexible: json['confirmed_flexible'] as bool? ?? false,
        hourlyRate: (json['hourly_rate'] as num?)?.toDouble(),
        estimatedHoursMin: (json['estimated_hours_min'] as num?)?.toDouble(),
        estimatedHoursMax: (json['estimated_hours_max'] as num?)?.toDouble(),
        agreedRate: (json['agreed_rate'] as num?)?.toDouble(),
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        jobStatus: json['job_status'] as String?,
        totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
        serviceTypeId: json['service_type_id'] as String?,
        locationArea: json['location_area'] as String?,
        markedDoneAt: json['marked_done_at'] != null
            ? DateTime.parse(json['marked_done_at'] as String)
            : null,
        cancelReason: json['cancel_reason'] as String?,
        cancelledByClient: json['cancelled_by_client'] as bool? ?? false,
        cancelledByMe: json['cancelled_by_me'] as bool? ?? false,
        jobUpdatedAt: json['job_updated_at'] != null
            ? DateTime.parse(json['job_updated_at'] as String)
            : null,
        startedAt: json['started_at'] != null
            ? DateTime.parse(json['started_at'] as String)
            : null,
      );
}
