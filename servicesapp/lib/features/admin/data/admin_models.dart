import '../../../core/constants/enums.dart';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;
double? _double(Object? v) => (v as num?)?.toDouble();
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// Resposta de `admin_whoami()`: a conta é administradora? A sessão já
/// tem o segundo fator (aal2)?
class AdminAccess {
  const AdminAccess({required this.isAdmin, required this.hasMfa});

  final bool isAdmin;
  final bool hasMfa;
}

/// `admin_overview(p_days)`. Os números de pedidos são dos pedidos
/// criados no período.
class AdminOverview {
  const AdminOverview({
    required this.clientsTotal,
    required this.workersTotal,
    required this.clientsNew,
    required this.workersNew,
    required this.jobsPublished,
    required this.jobsWithProposal24h,
    required this.avgHoursToFirstProposal,
    required this.jobsAccepted,
    required this.jobsCompleted,
    required this.jobsCancelled,
    required this.jobsNoResponse,
    required this.avgRating,
    required this.ratingsCount,
    required this.workersPro,
    required this.workersProPlus,
    required this.alertOpenWithoutProposals,
    required this.alertReports7d,
    required this.alertFleetCardsPending,
    required this.alertPlansEnding7d,
  });

  final int clientsTotal;
  final int workersTotal;
  final int clientsNew;
  final int workersNew;
  final int jobsPublished;
  final int jobsWithProposal24h;
  final double? avgHoursToFirstProposal;
  final int jobsAccepted;
  final int jobsCompleted;
  final int jobsCancelled;
  final int jobsNoResponse;
  final double? avgRating;
  final int ratingsCount;
  final int workersPro;
  final int workersProPlus;
  final int alertOpenWithoutProposals;
  final int alertReports7d;
  final int alertFleetCardsPending;
  final int alertPlansEnding7d;

  factory AdminOverview.fromJson(Map<String, dynamic> json) => AdminOverview(
        clientsTotal: _int(json['clients_total']),
        workersTotal: _int(json['workers_total']),
        clientsNew: _int(json['clients_new']),
        workersNew: _int(json['workers_new']),
        jobsPublished: _int(json['jobs_published']),
        jobsWithProposal24h: _int(json['jobs_with_proposal_24h']),
        avgHoursToFirstProposal: _double(json['avg_hours_to_first_proposal']),
        jobsAccepted: _int(json['jobs_accepted']),
        jobsCompleted: _int(json['jobs_completed']),
        jobsCancelled: _int(json['jobs_cancelled']),
        jobsNoResponse: _int(json['jobs_no_response']),
        avgRating: _double(json['avg_rating']),
        ratingsCount: _int(json['ratings_count']),
        workersPro: _int(json['workers_pro']),
        workersProPlus: _int(json['workers_pro_plus']),
        alertOpenWithoutProposals:
            _int(json['alert_open_without_proposals_12h']),
        alertReports7d: _int(json['alert_reports_7d']),
        alertFleetCardsPending: _int(json['alert_fleet_cards_pending']),
        alertPlansEnding7d: _int(json['alert_plans_ending_7d']),
      );
}

/// Uma linha de `admin_list_workers`.
class AdminWorkerRow {
  const AdminWorkerRow({
    required this.workerId,
    required this.fullName,
    required this.phone,
    required this.avatarUrl,
    required this.locationName,
    required this.tier,
    required this.planEndsAt,
    required this.createdAt,
    required this.lastSignInAt,
    required this.jobsCompleted,
    required this.avgRating,
    required this.ratingCount,
    required this.totalCount,
  });

  final String workerId;
  final String fullName;
  final String? phone;
  final String? avatarUrl;
  final String? locationName;
  final WorkerPlanTier tier;
  final DateTime? planEndsAt;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;
  final int jobsCompleted;
  final double? avgRating;
  final int ratingCount;

  /// Total de linhas do filtro (igual em todas), para a paginação.
  final int totalCount;

  factory AdminWorkerRow.fromJson(Map<String, dynamic> json) => AdminWorkerRow(
        workerId: json['worker_id'] as String,
        fullName: json['full_name'] as String? ?? '',
        phone: json['phone'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        locationName: json['location_name'] as String?,
        tier: WorkerPlanTier.fromValue(json['tier'] as String?),
        planEndsAt: _date(json['plan_ends_at']),
        createdAt: _date(json['created_at']),
        lastSignInAt: _date(json['last_sign_in_at']),
        jobsCompleted: _int(json['jobs_completed']),
        avgRating: _double(json['avg_rating']),
        ratingCount: _int(json['rating_count']),
        totalCount: _int(json['total_count']),
      );
}

/// Plano gravado em `worker_plans` (o que o admin escreveu), mais o plano
/// em vigor hoje (`activeTier`: um Pro com a data de fim já passada conta
/// como Grátis).
class AdminWorkerPlan {
  const AdminWorkerPlan({
    required this.activeTier,
    required this.tier,
    required this.startsAt,
    required this.endsAt,
    required this.verifiedAt,
    required this.notes,
  });

  final WorkerPlanTier activeTier;

  /// `null` = nunca teve plano gravado.
  final WorkerPlanTier? tier;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? verifiedAt;
  final String? notes;

  factory AdminWorkerPlan.fromJson(Map<String, dynamic> json) {
    final tier = json['tier'] as String?;
    return AdminWorkerPlan(
      activeTier: WorkerPlanTier.fromValue(json['active_tier'] as String?),
      tier: tier == null ? null : WorkerPlanTier.fromValue(tier),
      startsAt: _date(json['starts_at']),
      endsAt: _date(json['ends_at']),
      verifiedAt: _date(json['verified_at']),
      notes: json['notes'] as String?,
    );
  }
}

class AdminMonthCount {
  const AdminMonthCount({required this.month, required this.count});

  /// `YYYY-MM`.
  final String month;
  final int count;
}

class AdminPlanChange {
  const AdminPlanChange({
    required this.createdAt,
    required this.tier,
    required this.endsAt,
  });

  final DateTime? createdAt;
  final WorkerPlanTier tier;
  final DateTime? endsAt;
}

/// `admin_get_worker(p_worker_id)`.
class AdminWorkerDetail {
  const AdminWorkerDetail({
    required this.workerId,
    required this.fullName,
    required this.phone,
    required this.avatarUrl,
    required this.createdAt,
    required this.lastSignInAt,
    required this.locationName,
    required this.radiusKm,
    required this.services,
    required this.proposalsSent,
    required this.proposalsAccepted,
    required this.avgResponseHours,
    required this.jobsCompleted,
    required this.jobsActive,
    required this.jobsCancelledByWorker,
    required this.trackedHours,
    required this.estimatedRevenue,
    required this.helperJobs,
    required this.avgRating,
    required this.ratingCount,
    required this.jobsThisMonth,
    required this.monthlyJobs,
    required this.plan,
    required this.planHistory,
  });

  final String workerId;
  final String fullName;
  final String? phone;
  final String? avatarUrl;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;
  final String? locationName;
  final int? radiusKm;
  final List<String> services;
  final int proposalsSent;
  final int proposalsAccepted;
  final double? avgResponseHours;
  final int jobsCompleted;
  final int jobsActive;
  final int jobsCancelledByWorker;
  final double trackedHours;
  final double estimatedRevenue;
  final int helperJobs;
  final double? avgRating;
  final int ratingCount;
  final int jobsThisMonth;
  final List<AdminMonthCount> monthlyJobs;
  final AdminWorkerPlan plan;
  final List<AdminPlanChange> planHistory;

  factory AdminWorkerDetail.fromJson(Map<String, dynamic> json) {
    final monthly = (json['monthly_jobs'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((m) => AdminMonthCount(
              month: m['month'] as String? ?? '',
              count: _int(m['count']),
            ))
        .toList();
    final history = (json['plan_history'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((h) {
      final details = (h['details'] as Map?)?.cast<String, dynamic>() ?? {};
      return AdminPlanChange(
        createdAt: _date(h['created_at']),
        tier: WorkerPlanTier.fromValue(details['tier'] as String?),
        endsAt: _date(details['ends_at']),
      );
    }).toList();
    return AdminWorkerDetail(
      workerId: json['worker_id'] as String,
      fullName: json['full_name'] as String? ?? '',
      phone: json['phone'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: _date(json['created_at']),
      lastSignInAt: _date(json['last_sign_in_at']),
      locationName: json['location_name'] as String?,
      radiusKm: (json['radius_km'] as num?)?.toInt(),
      services: (json['services'] as List? ?? const []).cast<String>(),
      proposalsSent: _int(json['proposals_sent']),
      proposalsAccepted: _int(json['proposals_accepted']),
      avgResponseHours: _double(json['avg_response_hours']),
      jobsCompleted: _int(json['jobs_completed']),
      jobsActive: _int(json['jobs_active']),
      jobsCancelledByWorker: _int(json['jobs_cancelled_by_worker']),
      trackedHours: _double(json['tracked_hours']) ?? 0,
      estimatedRevenue: _double(json['estimated_revenue']) ?? 0,
      helperJobs: _int(json['helper_jobs']),
      avgRating: _double(json['avg_rating']),
      ratingCount: _int(json['rating_count']),
      jobsThisMonth: _int(json['jobs_this_month']),
      monthlyJobs: monthly,
      plan: AdminWorkerPlan.fromJson(
        (json['plan'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      planHistory: history,
    );
  }
}
