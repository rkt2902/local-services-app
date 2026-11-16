import '../../../core/constants/enums.dart';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;
double? _double(Object? v) => (v as num?)?.toDouble();
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
List<Map<String, dynamic>> _list(Object? v) => v is List
    ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
    : const [];
Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const {};

/// Estado do pedido vindo da BD; valores desconhecidos não rebentam o
/// painel (ficam `null` e mostram o texto cru).
JobStatus? adminJobStatusOrNull(String? value) {
  if (value == null) return null;
  try {
    return JobStatus.fromValue(value);
  } on ArgumentError {
    return null;
  }
}

/// O que a pesquisa global encontrou.
enum AdminSearchKind {
  job,
  client,
  worker;

  static AdminSearchKind? fromValue(String? v) => switch (v) {
    'job' => AdminSearchKind.job,
    'client' => AdminSearchKind.client,
    'worker' => AdminSearchKind.worker,
    _ => null,
  };
}

/// Uma linha de `admin_search(q)`.
class AdminSearchHit {
  const AdminSearchHit({
    required this.kind,
    required this.targetId,
    required this.title,
    required this.subtitle,
    required this.status,
  });

  final AdminSearchKind kind;
  final String targetId;
  final String title;
  final String subtitle;
  final String? status;

  /// Rota da ficha no painel.
  String get route => switch (kind) {
    AdminSearchKind.job => '/admin/pedidos/$targetId',
    AdminSearchKind.client => '/admin/clientes/$targetId',
    AdminSearchKind.worker => '/admin/workers/$targetId',
  };

  static AdminSearchHit? fromJson(Map<String, dynamic> json) {
    final kind = AdminSearchKind.fromValue(json['kind'] as String?);
    final id = json['target_id'] as String?;
    if (kind == null || id == null) return null;
    return AdminSearchHit(
      kind: kind,
      targetId: id,
      title: _str(json['title']) ?? 'Sem nome',
      subtitle: (json['subtitle'] as String?) ?? '',
      status: json['status'] as String?,
    );
  }
}

/// Filtros da lista de pedidos. `null` = todos.
class AdminJobsFilter {
  const AdminJobsFilter({
    this.status,
    this.serviceTypeId,
    this.area = '',
    this.lastDays,
    this.withReport = false,
    this.directOnly = false,
    this.withHelpers = false,
    this.page = 0,
  });

  final JobStatus? status;
  final String? serviceTypeId;
  final String area;

  /// Criados nos últimos N dias; `null` = desde sempre.
  final int? lastDays;
  final bool withReport;
  final bool directOnly;
  final bool withHelpers;
  final int page;

  AdminJobsFilter copyWith({
    JobStatus? Function()? status,
    String? Function()? serviceTypeId,
    String? area,
    int? Function()? lastDays,
    bool? withReport,
    bool? directOnly,
    bool? withHelpers,
    int? page,
  }) {
    return AdminJobsFilter(
      status: status != null ? status() : this.status,
      serviceTypeId: serviceTypeId != null
          ? serviceTypeId()
          : this.serviceTypeId,
      area: area ?? this.area,
      lastDays: lastDays != null ? lastDays() : this.lastDays,
      withReport: withReport ?? this.withReport,
      directOnly: directOnly ?? this.directOnly,
      withHelpers: withHelpers ?? this.withHelpers,
      // Mudar um filtro volta à primeira página.
      page: page ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AdminJobsFilter &&
      other.status == status &&
      other.serviceTypeId == serviceTypeId &&
      other.area == area &&
      other.lastDays == lastDays &&
      other.withReport == withReport &&
      other.directOnly == directOnly &&
      other.withHelpers == withHelpers &&
      other.page == page;

  @override
  int get hashCode => Object.hash(
    status,
    serviceTypeId,
    area,
    lastDays,
    withReport,
    directOnly,
    withHelpers,
    page,
  );
}

/// Uma linha de `admin_list_jobs`.
class AdminJobRow {
  const AdminJobRow({
    required this.jobId,
    required this.serviceName,
    required this.clientId,
    required this.clientName,
    required this.workerId,
    required this.workerName,
    required this.locationArea,
    required this.status,
    required this.statusValue,
    required this.proposalCount,
    required this.dateMode,
    required this.preferredDate,
    required this.confirmedDate,
    required this.createdAt,
    required this.hasReport,
    required this.isDirect,
    required this.hasHelpers,
    required this.totalCount,
  });

  final String jobId;
  final String? serviceName;
  final String? clientId;
  final String? clientName;
  final String? workerId;
  final String? workerName;
  final String? locationArea;
  final JobStatus? status;
  final String statusValue;
  final int proposalCount;
  final String? dateMode;
  final DateTime? preferredDate;
  final DateTime? confirmedDate;
  final DateTime? createdAt;
  final bool hasReport;
  final bool isDirect;
  final bool hasHelpers;
  final int totalCount;

  factory AdminJobRow.fromJson(Map<String, dynamic> json) {
    final status = (json['status'] as String?) ?? '';
    return AdminJobRow(
      jobId: json['job_id'] as String,
      serviceName: _str(json['service_name']),
      clientId: json['client_id'] as String?,
      clientName: _str(json['client_name']),
      workerId: json['worker_id'] as String?,
      workerName: _str(json['worker_name']),
      locationArea: _str(json['location_area']),
      status: adminJobStatusOrNull(status),
      statusValue: status,
      proposalCount: _int(json['proposal_count']),
      dateMode: json['date_mode'] as String?,
      preferredDate: _date(json['preferred_date']),
      confirmedDate: _date(json['confirmed_date']),
      createdAt: _date(json['created_at']),
      hasReport: json['has_report'] as bool? ?? false,
      isDirect: json['is_direct'] as bool? ?? false,
      hasHelpers: json['has_helpers'] as bool? ?? false,
      totalCount: _int(json['total_count']),
    );
  }
}

/// Pessoa ligada a um pedido (cliente ou jardineiro).
class AdminPersonRef {
  const AdminPersonRef({
    required this.id,
    required this.fullName,
    required this.avatarUrl,
    required this.deleted,
  });

  final String id;
  final String? fullName;
  final String? avatarUrl;
  final bool deleted;

  static AdminPersonRef? fromJson(Object? v) {
    final json = _map(v);
    final id = json['id'] as String?;
    if (id == null) return null;
    return AdminPersonRef(
      id: id,
      fullName: _str(json['full_name']),
      avatarUrl: _str(json['avatar_url']),
      deleted: json['deleted'] as bool? ?? false,
    );
  }
}

/// Quem fez um evento da linha do tempo.
enum AdminActorKind {
  client,
  worker,
  helper,
  admin,
  system,
  user;

  static AdminActorKind fromValue(String? v) => switch (v) {
    'client' => AdminActorKind.client,
    'worker' => AdminActorKind.worker,
    'helper' => AdminActorKind.helper,
    'admin' => AdminActorKind.admin,
    'user' => AdminActorKind.user,
    _ => AdminActorKind.system,
  };
}

/// Um evento de `job_events` (ou uma ação de admin sobre o pedido).
class AdminJobEvent {
  const AdminJobEvent({
    required this.at,
    required this.type,
    required this.actorKind,
    required this.actorName,
    required this.data,
  });

  final DateTime? at;
  final String type;
  final AdminActorKind actorKind;
  final String? actorName;
  final Map<String, dynamic> data;

  /// Evento reconstruído dos carimbos (pedido anterior à 0078).
  bool get isBackfill => data['backfill'] == true;

  factory AdminJobEvent.fromJson(Map<String, dynamic> json) => AdminJobEvent(
    at: _date(json['at']),
    type: (json['type'] as String?) ?? '',
    actorKind: AdminActorKind.fromValue(json['actor_kind'] as String?),
    actorName: _str(json['actor_name']),
    data: _map(json['data']),
  );
}

class AdminProposalItem {
  const AdminProposalItem({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.status,
    required this.isAccepted,
    required this.pricingMode,
    required this.hourlyRate,
    required this.totalPrice,
    required this.hoursMin,
    required this.hoursMax,
    required this.daysMin,
    required this.daysMax,
    required this.peopleNeeded,
    required this.includes,
    required this.notes,
    required this.scheduledDate,
    required this.scheduledTime,
    required this.validUntil,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? workerId;
  final String? workerName;
  final String status;
  final bool isAccepted;
  final String pricingMode;
  final double? hourlyRate;
  final double? totalPrice;
  final double? hoursMin;
  final double? hoursMax;
  final int? daysMin;
  final int? daysMax;
  final int peopleNeeded;
  final List<String> includes;
  final String? notes;
  final DateTime? scheduledDate;
  final String? scheduledTime;
  final DateTime? validUntil;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isFixedTotal => pricingMode == 'fixed_total';

  factory AdminProposalItem.fromJson(Map<String, dynamic> json) =>
      AdminProposalItem(
        id: json['id'] as String,
        workerId: json['worker_id'] as String?,
        workerName: _str(json['worker_name']),
        status: (json['status'] as String?) ?? '',
        isAccepted: json['is_accepted'] as bool? ?? false,
        pricingMode: (json['pricing_mode'] as String?) ?? 'hourly',
        hourlyRate: _double(json['hourly_rate']),
        totalPrice: _double(json['total_price']),
        hoursMin: _double(json['hours_min']),
        hoursMax: _double(json['hours_max']),
        daysMin: (json['days_min'] as num?)?.toInt(),
        daysMax: (json['days_max'] as num?)?.toInt(),
        peopleNeeded: _int(json['people_needed']),
        includes:
            (json['includes'] as List?)?.whereType<String>().toList() ??
            const [],
        notes: _str(json['notes']),
        scheduledDate: _date(json['scheduled_date']),
        scheduledTime: _str(json['scheduled_time']),
        validUntil: _date(json['valid_until']),
        createdAt: _date(json['created_at']),
        updatedAt: _date(json['updated_at']),
      );
}

class AdminHelpAcceptanceItem {
  const AdminHelpAcceptanceItem({
    required this.workerId,
    required this.workerName,
    required this.status,
    required this.agreedRate,
    required this.broughtEquipment,
    required this.message,
    required this.createdAt,
  });

  final String? workerId;
  final String? workerName;
  final String status;
  final double? agreedRate;
  final bool broughtEquipment;
  final String? message;
  final DateTime? createdAt;

  factory AdminHelpAcceptanceItem.fromJson(Map<String, dynamic> json) =>
      AdminHelpAcceptanceItem(
        workerId: json['worker_id'] as String?,
        workerName: _str(json['worker_name']),
        status: (json['status'] as String?) ?? '',
        agreedRate: _double(json['agreed_rate']),
        broughtEquipment: json['brought_equipment'] as bool? ?? false,
        message: _str(json['message']),
        createdAt: _date(json['created_at']),
      );
}

class AdminHelpRequestItem {
  const AdminHelpRequestItem({
    required this.id,
    required this.status,
    required this.slotsNeeded,
    required this.equipmentRequired,
    required this.afterConfirmation,
    required this.createdAt,
    required this.acceptances,
  });

  final String id;
  final String status;
  final int slotsNeeded;
  final bool equipmentRequired;
  final bool afterConfirmation;
  final DateTime? createdAt;
  final List<AdminHelpAcceptanceItem> acceptances;

  factory AdminHelpRequestItem.fromJson(Map<String, dynamic> json) =>
      AdminHelpRequestItem(
        id: json['id'] as String,
        status: (json['status'] as String?) ?? '',
        slotsNeeded: _int(json['slots_needed']),
        equipmentRequired: json['equipment_required'] as bool? ?? false,
        afterConfirmation: json['after_confirmation'] as bool? ?? false,
        createdAt: _date(json['created_at']),
        acceptances: _list(
          json['acceptances'],
        ).map(AdminHelpAcceptanceItem.fromJson).toList(),
      );
}

class AdminNotificationItem {
  const AdminNotificationItem({
    required this.userName,
    required this.userRole,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    required this.hadPushToken,
    required this.hasPushTokenNow,
  });

  final String? userName;

  /// 'client', 'worker' (o aceite) ou 'other' (outros jardineiros, ajudantes).
  final String userRole;
  final String type;
  final String? title;
  final String? body;
  final bool read;
  final DateTime? createdAt;
  final bool hadPushToken;
  final bool hasPushTokenNow;

  factory AdminNotificationItem.fromJson(Map<String, dynamic> json) =>
      AdminNotificationItem(
        userName: _str(json['user_name']),
        userRole: (json['user_role'] as String?) ?? 'other',
        type: (json['type'] as String?) ?? '',
        title: _str(json['title']),
        body: _str(json['body']),
        read: json['read'] as bool? ?? false,
        createdAt: _date(json['created_at']),
        hadPushToken: json['had_push_token'] as bool? ?? false,
        hasPushTokenNow: json['has_push_token_now'] as bool? ?? false,
      );
}

class AdminReportItem {
  const AdminReportItem({
    required this.reporterName,
    required this.description,
    required this.createdAt,
  });

  final String? reporterName;
  final String description;
  final DateTime? createdAt;

  factory AdminReportItem.fromJson(Map<String, dynamic> json) =>
      AdminReportItem(
        reporterName: _str(json['reporter_name']),
        description: (json['description'] as String?) ?? '',
        createdAt: _date(json['created_at']),
      );
}

class AdminRatingItem {
  const AdminRatingItem({
    required this.jobId,
    required this.personName,
    required this.stars,
    required this.comment,
    required this.createdAt,
  });

  final String? jobId;

  /// Quem avaliou (na ficha do pedido e em "recebidas") ou quem foi
  /// avaliado (em "dadas").
  final String? personName;
  final int stars;
  final String? comment;
  final DateTime? createdAt;

  factory AdminRatingItem.fromJson(Map<String, dynamic> json) =>
      AdminRatingItem(
        jobId: json['job_id'] as String?,
        personName: _str(json['rater_name']) ?? _str(json['ratee_name']),
        stars: _int(json['stars']),
        comment: _str(json['comment']),
        createdAt: _date(json['created_at']),
      );
}

/// `admin_get_job(id)`.
class AdminJobDetail {
  const AdminJobDetail({
    required this.jobId,
    required this.status,
    required this.statusValue,
    required this.proposalCount,
    required this.serviceName,
    required this.description,
    required this.sizeEstimate,
    required this.urgent,
    required this.locationArea,
    required this.hasAddress,
    required this.dateMode,
    required this.preferredDate,
    required this.availabilityText,
    required this.confirmedDate,
    required this.confirmedTime,
    required this.createdAt,
    required this.startedAt,
    required this.markedDoneAt,
    required this.expiresAt,
    required this.autoConfirmAt,
    required this.directUntil,
    required this.isDirect,
    required this.directStatus,
    required this.cancelReason,
    required this.cancelReasonDetail,
    required this.reopenedFrom,
    required this.photoCount,
    required this.client,
    required this.worker,
    required this.directWorker,
    required this.timeline,
    required this.views,
    required this.proposals,
    required this.team,
    required this.notifications,
    required this.reports,
    required this.ratings,
  });

  final String jobId;
  final JobStatus? status;
  final String statusValue;
  final int proposalCount;
  final String? serviceName;
  final String? description;
  final String? sizeEstimate;
  final bool urgent;
  final String? locationArea;
  final bool hasAddress;
  final String? dateMode;
  final DateTime? preferredDate;
  final String? availabilityText;
  final DateTime? confirmedDate;
  final String? confirmedTime;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? markedDoneAt;
  final DateTime? expiresAt;
  final DateTime? autoConfirmAt;
  final DateTime? directUntil;
  final bool isDirect;
  final String? directStatus;
  final String? cancelReason;
  final String? cancelReasonDetail;
  final String? reopenedFrom;
  final int photoCount;
  final AdminPersonRef? client;
  final AdminPersonRef? worker;
  final AdminPersonRef? directWorker;
  final List<AdminJobEvent> timeline;
  final int views;
  final List<AdminProposalItem> proposals;
  final List<AdminHelpRequestItem> team;
  final List<AdminNotificationItem> notifications;
  final List<AdminReportItem> reports;
  final List<AdminRatingItem> ratings;

  factory AdminJobDetail.fromJson(Map<String, dynamic> json) {
    final status = (json['status'] as String?) ?? '';
    return AdminJobDetail(
      jobId: json['job_id'] as String,
      status: adminJobStatusOrNull(status),
      statusValue: status,
      proposalCount: _int(json['proposal_count']),
      serviceName: _str(json['service_name']),
      description: _str(json['description']),
      sizeEstimate: _str(json['size_estimate']),
      urgent: json['urgency'] == 'urgent',
      locationArea: _str(json['location_area']),
      hasAddress: json['has_address'] as bool? ?? false,
      dateMode: json['date_mode'] as String?,
      preferredDate: _date(json['preferred_date']),
      availabilityText: _str(json['availability_text']),
      confirmedDate: _date(json['confirmed_date']),
      confirmedTime: _str(json['confirmed_time']),
      createdAt: _date(json['created_at']),
      startedAt: _date(json['started_at']),
      markedDoneAt: _date(json['marked_done_at']),
      expiresAt: _date(json['expires_at']),
      autoConfirmAt: _date(json['auto_confirm_at']),
      directUntil: _date(json['direct_until']),
      isDirect: json['is_direct'] as bool? ?? false,
      directStatus: json['direct_status'] as String?,
      cancelReason: _str(json['cancel_reason']),
      cancelReasonDetail: _str(json['cancel_reason_detail']),
      reopenedFrom: json['reopened_from'] as String?,
      photoCount: _int(json['photo_count']),
      client: AdminPersonRef.fromJson(json['client']),
      worker: AdminPersonRef.fromJson(json['worker']),
      directWorker: AdminPersonRef.fromJson(json['direct_worker']),
      timeline: _list(json['timeline']).map(AdminJobEvent.fromJson).toList(),
      views: _int(json['views']),
      proposals: _list(
        json['proposals'],
      ).map(AdminProposalItem.fromJson).toList(),
      team: _list(json['team']).map(AdminHelpRequestItem.fromJson).toList(),
      notifications: _list(
        json['notifications'],
      ).map(AdminNotificationItem.fromJson).toList(),
      reports: _list(json['reports']).map(AdminReportItem.fromJson).toList(),
      ratings: _list(json['ratings']).map(AdminRatingItem.fromJson).toList(),
    );
  }
}

/// Uma foto de `admin_get_job_photos`. [url] é o endereço público.
class AdminJobPhoto {
  const AdminJobPhoto({
    required this.kind,
    required this.url,
    required this.takenBy,
    required this.createdAt,
  });

  /// 'request' (pedido), 'before', 'after' ou 'completion'.
  final String kind;
  final String url;
  final String takenBy;
  final DateTime? createdAt;
}

/// Filtros da lista de clientes.
class AdminClientsFilter {
  const AdminClientsFilter({
    this.search = '',
    this.state,
    this.withReports = false,
    this.page = 0,
  });

  final String search;

  /// `null` = todas; 'active' | 'deleted'.
  final String? state;
  final bool withReports;
  final int page;

  AdminClientsFilter copyWith({
    String? search,
    String? Function()? state,
    bool? withReports,
    int? page,
  }) => AdminClientsFilter(
    search: search ?? this.search,
    state: state != null ? state() : this.state,
    withReports: withReports ?? this.withReports,
    page: page ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      other is AdminClientsFilter &&
      other.search == search &&
      other.state == state &&
      other.withReports == withReports &&
      other.page == page;

  @override
  int get hashCode => Object.hash(search, state, withReports, page);
}

/// Uma linha de `admin_list_clients`.
class AdminClientRow {
  const AdminClientRow({
    required this.clientId,
    required this.fullName,
    required this.email,
    required this.phoneMasked,
    required this.avatarUrl,
    required this.createdAt,
    required this.lastSignInAt,
    required this.deletedAt,
    required this.jobsTotal,
    required this.jobsActive,
    required this.avgRating,
    required this.ratingCount,
    required this.reportsCount,
    required this.totalCount,
  });

  final String clientId;
  final String? fullName;
  final String? email;
  final String? phoneMasked;
  final String? avatarUrl;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;
  final DateTime? deletedAt;
  final int jobsTotal;
  final int jobsActive;
  final double? avgRating;
  final int ratingCount;
  final int reportsCount;
  final int totalCount;

  factory AdminClientRow.fromJson(Map<String, dynamic> json) => AdminClientRow(
    clientId: json['client_id'] as String,
    fullName: _str(json['full_name']),
    email: _str(json['email']),
    phoneMasked: _str(json['phone_masked']),
    avatarUrl: _str(json['avatar_url']),
    createdAt: _date(json['created_at']),
    lastSignInAt: _date(json['last_sign_in_at']),
    deletedAt: _date(json['deleted_at']),
    jobsTotal: _int(json['jobs_total']),
    jobsActive: _int(json['jobs_active']),
    avgRating: _double(json['avg_rating']),
    ratingCount: _int(json['rating_count']),
    reportsCount: _int(json['reports_count']),
    totalCount: _int(json['total_count']),
  );
}

class AdminClientJob {
  const AdminClientJob({
    required this.jobId,
    required this.serviceName,
    required this.status,
    required this.statusValue,
    required this.proposalCount,
    required this.locationArea,
    required this.workerName,
    required this.createdAt,
    required this.hasReport,
  });

  final String jobId;
  final String? serviceName;
  final JobStatus? status;
  final String statusValue;
  final int proposalCount;
  final String? locationArea;
  final String? workerName;
  final DateTime? createdAt;
  final bool hasReport;

  factory AdminClientJob.fromJson(Map<String, dynamic> json) {
    final status = (json['status'] as String?) ?? '';
    return AdminClientJob(
      jobId: json['job_id'] as String,
      serviceName: _str(json['service_name']),
      status: adminJobStatusOrNull(status),
      statusValue: status,
      proposalCount: _int(json['proposal_count']),
      locationArea: _str(json['location_area']),
      workerName: _str(json['worker_name']),
      createdAt: _date(json['created_at']),
      hasReport: json['has_report'] as bool? ?? false,
    );
  }
}

class AdminClientReport {
  const AdminClientReport({
    required this.jobId,
    required this.byClient,
    required this.description,
    required this.createdAt,
  });

  final String? jobId;
  final bool byClient;
  final String description;
  final DateTime? createdAt;

  factory AdminClientReport.fromJson(Map<String, dynamic> json) =>
      AdminClientReport(
        jobId: json['job_id'] as String?,
        byClient: json['by_client'] as bool? ?? false,
        description: (json['description'] as String?) ?? '',
        createdAt: _date(json['created_at']),
      );
}

class AdminHistoryItem {
  const AdminHistoryItem({required this.action, required this.createdAt});

  final String action;
  final DateTime? createdAt;

  factory AdminHistoryItem.fromJson(Map<String, dynamic> json) =>
      AdminHistoryItem(
        action: (json['action'] as String?) ?? '',
        createdAt: _date(json['created_at']),
      );
}

/// `admin_get_client(id)`.
class AdminClientDetail {
  const AdminClientDetail({
    required this.clientId,
    required this.fullName,
    required this.email,
    required this.emailConfirmed,
    required this.phoneMasked,
    required this.hasPhone,
    required this.avatarUrl,
    required this.createdAt,
    required this.lastSignInAt,
    required this.deletedAt,
    required this.pushDevices,
    required this.jobs,
    required this.ratingsGiven,
    required this.ratingsReceived,
    required this.reports,
    required this.adminHistory,
  });

  final String clientId;
  final String? fullName;
  final String? email;
  final bool emailConfirmed;
  final String? phoneMasked;
  final bool hasPhone;
  final String? avatarUrl;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;
  final DateTime? deletedAt;
  final int pushDevices;
  final List<AdminClientJob> jobs;
  final List<AdminRatingItem> ratingsGiven;
  final List<AdminRatingItem> ratingsReceived;
  final List<AdminClientReport> reports;
  final List<AdminHistoryItem> adminHistory;

  factory AdminClientDetail.fromJson(Map<String, dynamic> json) =>
      AdminClientDetail(
        clientId: json['client_id'] as String,
        fullName: _str(json['full_name']),
        email: _str(json['email']),
        emailConfirmed: json['email_confirmed'] as bool? ?? false,
        phoneMasked: _str(json['phone_masked']),
        hasPhone: json['has_phone'] as bool? ?? false,
        avatarUrl: _str(json['avatar_url']),
        createdAt: _date(json['created_at']),
        lastSignInAt: _date(json['last_sign_in_at']),
        deletedAt: _date(json['deleted_at']),
        pushDevices: _int(json['push_devices']),
        jobs: _list(json['jobs']).map(AdminClientJob.fromJson).toList(),
        ratingsGiven: _list(
          json['ratings_given'],
        ).map(AdminRatingItem.fromJson).toList(),
        ratingsReceived: _list(
          json['ratings_received'],
        ).map(AdminRatingItem.fromJson).toList(),
        reports: _list(
          json['reports'],
        ).map(AdminClientReport.fromJson).toList(),
        adminHistory: _list(
          json['admin_history'],
        ).map(AdminHistoryItem.fromJson).toList(),
      );
}

/// Morada revelada por `admin_reveal_contact(id, 'address')`.
class AdminRevealedAddress {
  const AdminRevealedAddress({
    required this.addressText,
    required this.lat,
    required this.lng,
    required this.workerBaseLat,
    required this.workerBaseLng,
    required this.workerLocationName,
    required this.distanceKm,
  });

  final String? addressText;
  final double? lat;
  final double? lng;
  final double? workerBaseLat;
  final double? workerBaseLng;
  final String? workerLocationName;
  final double? distanceKm;

  factory AdminRevealedAddress.fromJson(Map<String, dynamic> json) =>
      AdminRevealedAddress(
        addressText: _str(json['address_text']),
        lat: _double(json['lat']),
        lng: _double(json['lng']),
        workerBaseLat: _double(json['worker_base_lat']),
        workerBaseLng: _double(json['worker_base_lng']),
        workerLocationName: _str(json['worker_location_name']),
        distanceKm: _double(json['distance_km']),
      );
}
