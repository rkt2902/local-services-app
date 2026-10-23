import '../../../core/constants/enums.dart';

class JobRequest {
  final String id;
  final String clientId;
  final String serviceTypeId;
  final String addressText;

  /// Localidade do pedido (ex.: "Lisboa"). Até haver proposta aceite, o
  /// jardineiro recebe `addressText` igual a isto e coordenadas
  /// arredondadas (migration 0043).
  final String? locationArea;
  final double locationLat;
  final double locationLng;
  final DateMode dateMode;
  final DateTime? preferredDate;
  final String? availabilityText;
  final Urgency? urgency;
  final SizeEstimate? sizeEstimate;
  final String description;
  final JobStatus status;
  final String? acceptedProposalId;
  final int proposalCount;
  final DateTime? confirmedDate;
  final String? confirmedTime;
  final bool confirmedFlexible;
  final DateTime expiresAt;
  final DateTime createdAt;
  final String? cancelledBy;
  final String? cancelReason;
  final String? cancelReasonDetail;
  final String? reopenedFrom;
  final int reopenCountClient;
  final int reopenCountWorker;
  final DateTime? rescheduleProposedDate;
  final String? rescheduleProposedTime;
  final bool? rescheduleProposedFlexible;
  final String? rescheduleProposedBy;
  final RescheduleStatus? rescheduleStatus;
  final String? cancelledWorkerId;
  final List<String> excludedWorkerIds;

  /// Caminho no bucket `job-photos` da foto que o worker juntou ao marcar
  /// como concluído (opcional, migration 0046).
  final String? completionPhotoPath;

  /// Quando o jardineiro carregou em "Iniciar trabalho" (migration 0052).
  /// Com o pedido `confirmed`, preenchido quer dizer "Em curso".
  final DateTime? startedAt;

  /// Fotos de "antes" (ao iniciar) e de "depois" (ao concluir), caminhos no
  /// bucket `job-photos`, até 3 cada (migration 0052).
  final List<String> beforePhotoPaths;
  final List<String> afterPhotoPaths;

  /// Quando o jardineiro marcou como concluído (migration 0046).
  final DateTime? markedDoneAt;

  /// Última alteração da linha. Num pedido cancelado ou concluído é,
  /// na prática, quando isso aconteceu (não há `cancelled_at`).
  final DateTime? updatedAt;

  /// Pedido direto ("Pedir de novo", migration 0057). O jardineiro
  /// escolhido; para os outros jardineiros chega sempre `null`.
  final String? directWorkerId;

  /// Trabalho concluído de onde veio o pedido direto.
  final String? directSourceJobId;

  /// Até quando só o jardineiro escolhido vê o pedido (decidido pelo
  /// servidor: a app só o mostra).
  final DateTime? directUntil;
  final DirectRequestStatus? directStatus;

  /// Pedido pelo cartão do jardineiro (0059). Para outros jardineiros chega
  /// sempre `null`.
  final DirectRequestOrigin? directOrigin;

  /// Interruptor "Se não puder, mostrar a outros jardineiros".
  final bool directAutoRelease;

  /// Com o pedido parado (`onHold`): "declined" ou "expired".
  final String? directHoldReason;

  /// Km além do raio de cada jardineiro em que o pedido também aparece
  /// (0062, 0 a 30). Sobe sozinho ao fim de 24h sem propostas ou quando o
  /// cliente carrega em "Mostrar a jardineiros mais longe".
  final int searchExtraKm;

  /// Quando o cliente recebeu "Ainda sem propostas" (0062). A partir daqui
  /// o pedido mostra as sugestões.
  final DateTime? noProposalsNudgedAt;

  const JobRequest({
    required this.id,
    required this.clientId,
    required this.serviceTypeId,
    required this.addressText,
    this.locationArea,
    required this.locationLat,
    required this.locationLng,
    this.dateMode = DateMode.flexible,
    this.preferredDate,
    this.availabilityText,
    this.urgency,
    this.sizeEstimate,
    required this.description,
    required this.status,
    this.acceptedProposalId,
    this.proposalCount = 0,
    this.confirmedDate,
    this.confirmedTime,
    this.confirmedFlexible = false,
    required this.expiresAt,
    required this.createdAt,
    this.cancelledBy,
    this.cancelReason,
    this.cancelReasonDetail,
    this.reopenedFrom,
    this.reopenCountClient = 0,
    this.reopenCountWorker = 0,
    this.rescheduleProposedDate,
    this.rescheduleProposedTime,
    this.rescheduleProposedFlexible,
    this.rescheduleProposedBy,
    this.rescheduleStatus,
    this.cancelledWorkerId,
    this.excludedWorkerIds = const [],
    this.completionPhotoPath,
    this.startedAt,
    this.beforePhotoPaths = const [],
    this.updatedAt,
    this.afterPhotoPaths = const [],
    this.markedDoneAt,
    this.directWorkerId,
    this.directSourceJobId,
    this.directUntil,
    this.directStatus,
    this.directOrigin,
    this.directAutoRelease = true,
    this.directHoldReason,
    this.searchExtraKm = 0,
    this.noProposalsNudgedAt,
  });

  /// Máximo de [searchExtraKm] (igual ao CHECK da 0062).
  static const maxSearchExtraKm = 30;

  /// Reservado ao jardineiro escolhido (o servidor decide quando acaba).
  bool get isDirectWaiting =>
      status == JobStatus.open && directStatus == DirectRequestStatus.waiting;

  /// Parado à espera da decisão do cliente (interruptor desligado, 0059).
  bool get isDirectOnHold =>
      status == JobStatus.open && directStatus == DirectRequestStatus.onHold;

  /// `confirmed` com início marcado: o trabalho está a decorrer.
  bool get isInProgress => status == JobStatus.confirmed && startedAt != null;

  /// Tempo entre o início e a marcação de concluído; `null` sem um dos dois.
  Duration? get workedDuration =>
      (startedAt != null && markedDoneAt != null)
          ? markedDoneAt!.difference(startedAt!)
          : null;

  factory JobRequest.fromJson(Map<String, dynamic> json) => JobRequest(
        id: json['id'] as String,
        clientId: json['client_id'] as String,
        serviceTypeId: json['service_type_id'] as String,
        addressText: json['address_text'] as String? ?? '',
        locationArea: json['location_area'] as String?,
        locationLat: (json['location_lat'] as num).toDouble(),
        locationLng: (json['location_lng'] as num).toDouble(),
        dateMode: json['date_mode'] != null
            ? DateMode.fromString(json['date_mode'] as String)
            : DateMode.flexible,
        preferredDate: json['preferred_date'] != null
            ? DateTime.parse(json['preferred_date'] as String)
            : null,
        availabilityText: json['availability_text'] as String?,
        urgency: json['urgency'] != null
            ? Urgency.fromString(json['urgency'] as String)
            : null,
        sizeEstimate: json['size_estimate'] != null
            ? SizeEstimate.fromString(json['size_estimate'] as String)
            : null,
        description: json['description'] as String,
        status: JobStatus.fromString(json['status'] as String),
        acceptedProposalId: json['accepted_proposal_id'] as String?,
        proposalCount: json['proposal_count'] as int? ?? 0,
        confirmedDate: json['confirmed_date'] != null
            ? DateTime.parse(json['confirmed_date'] as String)
            : null,
        confirmedTime: json['confirmed_time'] as String?,
        confirmedFlexible: json['confirmed_flexible'] as bool? ?? false,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        cancelledBy: json['cancelled_by'] as String?,
        cancelReason: json['cancel_reason'] as String?,
        cancelReasonDetail: json['cancel_reason_detail'] as String?,
        reopenedFrom: json['reopened_from'] as String?,
        reopenCountClient: json['reopen_count_client'] as int? ?? 0,
        reopenCountWorker: json['reopen_count_worker'] as int? ?? 0,
        rescheduleProposedDate: json['reschedule_proposed_date'] != null
            ? DateTime.parse(json['reschedule_proposed_date'] as String)
            : null,
        rescheduleProposedTime: json['reschedule_proposed_time'] as String?,
        rescheduleProposedFlexible:
            json['reschedule_proposed_flexible'] as bool?,
        rescheduleProposedBy: json['reschedule_proposed_by'] as String?,
        rescheduleStatus: RescheduleStatus.fromString(json['reschedule_status'] as String?),
        cancelledWorkerId: json['cancelled_worker_id'] as String?,
        excludedWorkerIds: List<String>.from(json['excluded_worker_ids'] as List? ?? []),
        completionPhotoPath: json['completion_photo_path'] as String?,
        startedAt: json['started_at'] != null
            ? DateTime.parse(json['started_at'] as String)
            : null,
        beforePhotoPaths:
            List<String>.from(json['before_photo_paths'] as List? ?? const []),
        afterPhotoPaths:
            List<String>.from(json['after_photo_paths'] as List? ?? const []),
        markedDoneAt: json['marked_done_at'] != null
            ? DateTime.parse(json['marked_done_at'] as String)
            : null,
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String)
            : null,
        directWorkerId: json['direct_worker_id'] as String?,
        directSourceJobId: json['direct_source_job_id'] as String?,
        directUntil: json['direct_until'] != null
            ? DateTime.parse(json['direct_until'] as String)
            : null,
        directStatus:
            DirectRequestStatus.fromString(json['direct_status'] as String?),
        directOrigin:
            DirectRequestOrigin.fromString(json['direct_origin'] as String?),
        directAutoRelease: json['direct_auto_release'] as bool? ?? true,
        directHoldReason: json['direct_hold_reason'] as String?,
        searchExtraKm: (json['search_extra_km'] as num?)?.toInt() ?? 0,
        noProposalsNudgedAt: json['no_proposals_nudged_at'] != null
            ? DateTime.parse(json['no_proposals_nudged_at'] as String)
            : null,
      );

  JobRequest copyWith({
    String? id,
    String? clientId,
    String? serviceTypeId,
    String? addressText,
    String? locationArea,
    double? locationLat,
    double? locationLng,
    DateMode? dateMode,
    DateTime? preferredDate,
    String? availabilityText,
    Urgency? urgency,
    SizeEstimate? sizeEstimate,
    String? description,
    JobStatus? status,
    String? acceptedProposalId,
    int? proposalCount,
    DateTime? confirmedDate,
    String? confirmedTime,
    bool? confirmedFlexible,
    DateTime? expiresAt,
    DateTime? createdAt,
    String? cancelledBy,
    String? cancelReason,
    String? cancelReasonDetail,
    String? reopenedFrom,
    int? reopenCountClient,
    int? reopenCountWorker,
    DateTime? rescheduleProposedDate,
    String? rescheduleProposedTime,
    bool? rescheduleProposedFlexible,
    String? rescheduleProposedBy,
    RescheduleStatus? rescheduleStatus,
    String? cancelledWorkerId,
    List<String>? excludedWorkerIds,
    String? completionPhotoPath,
    DateTime? startedAt,
    List<String>? beforePhotoPaths,
    List<String>? afterPhotoPaths,
    DateTime? markedDoneAt,
    DateTime? updatedAt,
    String? directWorkerId,
    String? directSourceJobId,
    DateTime? directUntil,
    DirectRequestStatus? directStatus,
  }) =>
      JobRequest(
        id: id ?? this.id,
        clientId: clientId ?? this.clientId,
        serviceTypeId: serviceTypeId ?? this.serviceTypeId,
        addressText: addressText ?? this.addressText,
        locationArea: locationArea ?? this.locationArea,
        locationLat: locationLat ?? this.locationLat,
        locationLng: locationLng ?? this.locationLng,
        dateMode: dateMode ?? this.dateMode,
        preferredDate: preferredDate ?? this.preferredDate,
        availabilityText: availabilityText ?? this.availabilityText,
        urgency: urgency ?? this.urgency,
        sizeEstimate: sizeEstimate ?? this.sizeEstimate,
        description: description ?? this.description,
        status: status ?? this.status,
        acceptedProposalId: acceptedProposalId ?? this.acceptedProposalId,
        proposalCount: proposalCount ?? this.proposalCount,
        confirmedDate: confirmedDate ?? this.confirmedDate,
        confirmedTime: confirmedTime ?? this.confirmedTime,
        confirmedFlexible: confirmedFlexible ?? this.confirmedFlexible,
        expiresAt: expiresAt ?? this.expiresAt,
        createdAt: createdAt ?? this.createdAt,
        cancelledBy: cancelledBy ?? this.cancelledBy,
        cancelReason: cancelReason ?? this.cancelReason,
        cancelReasonDetail: cancelReasonDetail ?? this.cancelReasonDetail,
        reopenedFrom: reopenedFrom ?? this.reopenedFrom,
        reopenCountClient: reopenCountClient ?? this.reopenCountClient,
        reopenCountWorker: reopenCountWorker ?? this.reopenCountWorker,
        rescheduleProposedDate:
            rescheduleProposedDate ?? this.rescheduleProposedDate,
        rescheduleProposedTime:
            rescheduleProposedTime ?? this.rescheduleProposedTime,
        rescheduleProposedFlexible:
            rescheduleProposedFlexible ?? this.rescheduleProposedFlexible,
        rescheduleProposedBy: rescheduleProposedBy ?? this.rescheduleProposedBy,
        rescheduleStatus: rescheduleStatus ?? this.rescheduleStatus,
        cancelledWorkerId: cancelledWorkerId ?? this.cancelledWorkerId,
        excludedWorkerIds: excludedWorkerIds ?? this.excludedWorkerIds,
        completionPhotoPath: completionPhotoPath ?? this.completionPhotoPath,
        startedAt: startedAt ?? this.startedAt,
        beforePhotoPaths: beforePhotoPaths ?? this.beforePhotoPaths,
        afterPhotoPaths: afterPhotoPaths ?? this.afterPhotoPaths,
        markedDoneAt: markedDoneAt ?? this.markedDoneAt,
        updatedAt: updatedAt ?? this.updatedAt,
        directWorkerId: directWorkerId ?? this.directWorkerId,
        directSourceJobId: directSourceJobId ?? this.directSourceJobId,
        directUntil: directUntil ?? this.directUntil,
        directStatus: directStatus ?? this.directStatus,
        directOrigin: directOrigin,
        directAutoRelease: directAutoRelease,
        directHoldReason: directHoldReason,
        searchExtraKm: searchExtraKm,
        noProposalsNudgedAt: noProposalsNudgedAt,
      );
}
