// Painel de suporte, fase B (migration 0079): casos, reportes, moderação,
// notas internas e registo.

int _int(Object? v) => (v as num?)?.toInt() ?? 0;
int? _intOrNull(Object? v) => (v as num?)?.toInt();
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
List<Map<String, dynamic>> _list(Object? v) => v is List
    ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
    : const [];
Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const {};

/// Motivos fixos das ações (iguais a `admin_assert_reason` na 0079).
enum AdminActionReason {
  userRequest('user_request', 'Pedido da pessoa'),
  appError('app_error', 'Erro da app'),
  termsViolation('terms_violation', 'Não cumpre os Termos'),
  illegalContent('illegal_content', 'Conteúdo ilegal'),
  personalData('personal_data', 'Dados pessoais expostos'),
  duplicate('duplicate', 'Repetido'),
  other('other', 'Outro');

  const AdminActionReason(this.value, this.label);

  final String value;
  final String label;

  static String labelOf(String? value) {
    for (final r in values) {
      if (r.value == value) return r.label;
    }
    return value ?? '—';
  }
}

/// Tipos de caso e prazos (docs/SUPORTE.md; a BD calcula o prazo).
enum AdminCaseKind {
  help('help', 'Ajuda', '1 dia útil'),
  report('report', 'Reporte de problema', '2 dias úteis'),
  abuse('abuse', 'Denúncia', '7 dias'),
  appeal('appeal', 'Contestação', '15 dias úteis'),
  complaint('complaint', 'Reclamação', '15 dias úteis'),
  gdpr('gdpr', 'Pedido RGPD', '1 mês'),
  deleteAccount('delete_account', 'Eliminar conta', '30 dias');

  const AdminCaseKind(this.value, this.label, this.deadline);

  final String value;
  final String label;
  final String deadline;

  static AdminCaseKind? fromValue(String? value) {
    for (final k in values) {
      if (k.value == value) return k;
    }
    return null;
  }
}

enum AdminCaseStatus {
  open('open', 'Aberto'),
  waitingUser('waiting_user', 'À espera da pessoa'),
  resolved('resolved', 'Resolvido');

  const AdminCaseStatus(this.value, this.label);

  final String value;
  final String label;

  static AdminCaseStatus fromValue(String? value) {
    for (final s in values) {
      if (s.value == value) return s;
    }
    return AdminCaseStatus.open;
  }
}

/// Semáforo do prazo: verde com folga, âmbar a menos de 24 horas,
/// vermelho passado.
enum AdminDeadlineTone { green, amber, red, done }

AdminDeadlineTone adminDeadlineTone(
  DateTime? due, {
  bool closed = false,
  DateTime? now,
}) {
  if (closed || due == null) return AdminDeadlineTone.done;
  final left = due.difference(now ?? DateTime.now());
  if (left.isNegative) return AdminDeadlineTone.red;
  if (left < const Duration(hours: 24)) return AdminDeadlineTone.amber;
  return AdminDeadlineTone.green;
}

/// Linha de `admin_list_cases`.
class AdminCaseRow {
  const AdminCaseRow({
    required this.caseId,
    required this.number,
    required this.kind,
    required this.kindValue,
    required this.status,
    required this.summary,
    required this.personId,
    required this.personName,
    required this.jobId,
    required this.ackDueAt,
    required this.dueAt,
    required this.firstReplyAt,
    required this.createdAt,
    required this.closedAt,
    required this.totalCount,
  });

  final String caseId;
  final int number;
  final AdminCaseKind? kind;
  final String kindValue;
  final AdminCaseStatus status;
  final String summary;
  final String? personId;
  final String? personName;
  final String? jobId;
  final DateTime? ackDueAt;
  final DateTime? dueAt;
  final DateTime? firstReplyAt;
  final DateTime? createdAt;
  final DateTime? closedAt;
  final int totalCount;

  bool get closed => status == AdminCaseStatus.resolved;

  /// O prazo que conta agora: a confirmação de receção enquanto não houve
  /// resposta, depois o prazo do tipo.
  DateTime? get nextDueAt =>
      firstReplyAt == null &&
          ackDueAt != null &&
          (dueAt == null || ackDueAt!.isBefore(dueAt!))
      ? ackDueAt
      : dueAt;

  factory AdminCaseRow.fromJson(Map<String, dynamic> json) => AdminCaseRow(
    caseId: json['case_id'] as String,
    number: _int(json['number']),
    kind: AdminCaseKind.fromValue(json['kind'] as String?),
    kindValue: (json['kind'] as String?) ?? '',
    status: AdminCaseStatus.fromValue(json['status'] as String?),
    summary: (json['summary'] as String?) ?? '',
    personId: json['person_id'] as String?,
    personName: _str(json['person_name']),
    jobId: json['job_id'] as String?,
    ackDueAt: _date(json['ack_due_at']),
    dueAt: _date(json['due_at']),
    firstReplyAt: _date(json['first_reply_at']),
    createdAt: _date(json['created_at']),
    closedAt: _date(json['closed_at']),
    totalCount: _int(json['total_count']),
  );
}

class AdminCaseNote {
  const AdminCaseNote({
    required this.id,
    required this.isReply,
    required this.body,
    required this.createdAt,
    required this.authorEmail,
  });

  final String id;

  /// `true` = resposta enviada por email; `false` = nota interna.
  final bool isReply;
  final String body;
  final DateTime? createdAt;
  final String? authorEmail;

  factory AdminCaseNote.fromJson(Map<String, dynamic> json) => AdminCaseNote(
    id: json['id'] as String,
    isReply: json['kind'] == 'reply',
    body: (json['body'] as String?) ?? '',
    createdAt: _date(json['created_at']),
    authorEmail: _str(json['author_email']),
  );
}

class AdminCaseReport {
  const AdminCaseReport({
    required this.id,
    required this.description,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String description;
  final String status;
  final DateTime? createdAt;

  factory AdminCaseReport.fromJson(Map<String, dynamic> json) =>
      AdminCaseReport(
        id: json['id'] as String,
        description: (json['description'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'new',
        createdAt: _date(json['created_at']),
      );
}

/// `admin_get_case(id)`.
class AdminCaseDetail {
  const AdminCaseDetail({
    required this.row,
    required this.decision,
    required this.contactEmail,
    required this.personRole,
    required this.personEmail,
    required this.jobService,
    required this.reports,
    required this.notes,
  });

  final AdminCaseRow row;
  final String? decision;
  final String? contactEmail;
  final String? personRole;
  final String? personEmail;
  final String? jobService;
  final List<AdminCaseReport> reports;
  final List<AdminCaseNote> notes;

  /// Para onde escrever: o email colado no caso ou o da conta.
  String? get replyEmail => contactEmail ?? personEmail;

  factory AdminCaseDetail.fromJson(Map<String, dynamic> json) =>
      AdminCaseDetail(
        row: AdminCaseRow.fromJson(json),
        decision: _str(json['decision']),
        contactEmail: _str(json['contact_email']),
        personRole: _str(json['person_role']),
        personEmail: _str(json['person_email']),
        jobService: _str(json['job_service']),
        reports: _list(json['reports']).map(AdminCaseReport.fromJson).toList(),
        notes: _list(json['notes']).map(AdminCaseNote.fromJson).toList(),
      );
}

/// Filtros da Caixa de suporte. `status` `null` = abertos e à espera.
class AdminCasesFilter {
  const AdminCasesFilter({this.status, this.kind, this.page = 0});

  /// `null`, um [AdminCaseStatus.value] ou `'all'`.
  final String? status;
  final AdminCaseKind? kind;
  final int page;

  AdminCasesFilter copyWith({
    Object? status = _keep,
    Object? kind = _keep,
    int? page,
  }) => AdminCasesFilter(
    status: identical(status, _keep) ? this.status : status as String?,
    kind: identical(kind, _keep) ? this.kind : kind as AdminCaseKind?,
    page: page ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      other is AdminCasesFilter &&
      other.status == status &&
      other.kind == kind &&
      other.page == page;

  @override
  int get hashCode => Object.hash(status, kind, page);
}

const _keep = Object();

/// Linha de `admin_list_reports`.
class AdminReportRow {
  const AdminReportRow({
    required this.reportId,
    required this.jobId,
    required this.serviceName,
    required this.reporterId,
    required this.reporterName,
    required this.reporterIsClient,
    required this.description,
    required this.status,
    required this.caseId,
    required this.caseNumber,
    required this.createdAt,
    required this.dueAt,
    required this.resolvedAt,
    required this.totalCount,
  });

  final String reportId;
  final String jobId;
  final String? serviceName;
  final String reporterId;
  final String? reporterName;
  final bool reporterIsClient;
  final String description;

  /// new, in_review, resolved, dismissed.
  final String status;
  final String? caseId;
  final int? caseNumber;
  final DateTime? createdAt;
  final DateTime? dueAt;
  final DateTime? resolvedAt;
  final int totalCount;

  bool get closed => status == 'resolved' || status == 'dismissed';

  factory AdminReportRow.fromJson(Map<String, dynamic> json) => AdminReportRow(
    reportId: json['report_id'] as String,
    jobId: json['job_id'] as String,
    serviceName: _str(json['service_name']),
    reporterId: json['reporter_id'] as String,
    reporterName: _str(json['reporter_name']),
    reporterIsClient: json['reporter_role'] == 'client',
    description: (json['description'] as String?) ?? '',
    status: (json['status'] as String?) ?? 'new',
    caseId: json['case_id'] as String?,
    caseNumber: _intOrNull(json['case_number']),
    createdAt: _date(json['created_at']),
    dueAt: _date(json['due_at']),
    resolvedAt: _date(json['resolved_at']),
    totalCount: _int(json['total_count']),
  );
}

/// Linha de `admin_list_ratings` (visíveis ou ocultas).
class AdminModerationRating {
  const AdminModerationRating({
    required this.ratingId,
    required this.jobId,
    required this.raterName,
    required this.rateeName,
    required this.stars,
    required this.comment,
    required this.createdAt,
    required this.hidden,
    required this.hiddenAt,
    required this.hiddenReason,
    required this.totalCount,
  });

  final String ratingId;
  final String? jobId;
  final String? raterName;
  final String? rateeName;
  final int stars;
  final String? comment;
  final DateTime? createdAt;
  final bool hidden;
  final DateTime? hiddenAt;
  final String? hiddenReason;
  final int totalCount;

  factory AdminModerationRating.fromJson(Map<String, dynamic> json) =>
      AdminModerationRating(
        ratingId: json['rating_id'] as String,
        jobId: json['job_id'] as String?,
        raterName: _str(json['rater_name']),
        rateeName: _str(json['ratee_name']),
        stars: _int(json['stars']),
        comment: _str(json['comment']),
        createdAt: _date(json['created_at']),
        hidden: json['hidden'] as bool? ?? false,
        hiddenAt: _date(json['hidden_at']),
        hiddenReason: _str(json['hidden_reason']),
        totalCount: _int(json['total_count']),
      );
}

/// Filtros das Avaliações.
typedef AdminRatingsQuery = ({
  bool hidden,
  int? stars,
  bool onlyWithComment,
  int page,
});

/// Nota interna numa ficha.
class AdminNote {
  const AdminNote({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.authorEmail,
  });

  final String id;
  final String body;
  final DateTime? createdAt;
  final String? authorEmail;

  factory AdminNote.fromJson(Map<String, dynamic> json) => AdminNote(
    id: json['note_id'] as String,
    body: (json['body'] as String?) ?? '',
    createdAt: _date(json['created_at']),
    authorEmail: _str(json['author_email']),
  );
}

/// Linha do Registo (`admin_list_actions`).
class AdminActionRow {
  const AdminActionRow({
    required this.id,
    required this.adminEmail,
    required this.action,
    required this.targetId,
    required this.details,
    required this.createdAt,
    required this.totalCount,
  });

  final String id;
  final String? adminEmail;
  final String action;
  final String? targetId;
  final Map<String, dynamic> details;
  final DateTime? createdAt;
  final int totalCount;

  String? get reason => _str(details['reason']);
  String? get note => _str(details['note']);

  factory AdminActionRow.fromJson(Map<String, dynamic> json) => AdminActionRow(
    id: json['action_id'] as String,
    adminEmail: _str(json['admin_email']),
    action: (json['action'] as String?) ?? '',
    targetId: json['target_id'] as String?,
    details: _map(json['details']),
    createdAt: _date(json['created_at']),
    totalCount: _int(json['total_count']),
  );
}

/// Filtros do Registo.
typedef AdminActionsQuery = ({bool includeReads, String? action, int page});
