import '../../../core/constants/enums.dart';

/// Plano do próprio jardineiro, de `get_my_plan()` (migration 0058).
class WorkerPlan {
  const WorkerPlan({
    required this.tier,
    required this.endsAt,
    required this.verified,
    required this.jobsThisMonth,
    required this.monthlyJobLimit,
  });

  /// Antes da 0058 aplicada (a RPC não existe): Grátis sem limite, para a
  /// conta não mostrar um limite que a BD ainda não aplica.
  static const unavailable = WorkerPlan(
    tier: WorkerPlanTier.free,
    endsAt: null,
    verified: false,
    jobsThisMonth: 0,
    monthlyJobLimit: null,
  );

  final WorkerPlanTier tier;

  /// `null` no Grátis ou num plano sem data de fim.
  final DateTime? endsAt;
  final bool verified;

  /// Trabalhos aceites este mês (hora de Lisboa).
  final int jobsThisMonth;

  /// Só no Grátis; `null` = sem limite.
  final int? monthlyJobLimit;

  bool get reachedLimit =>
      monthlyJobLimit != null && jobsThisMonth >= monthlyJobLimit!;

  factory WorkerPlan.fromJson(Map<String, dynamic> json) {
    final endsAt = json['ends_at'] as String?;
    return WorkerPlan(
      tier: WorkerPlanTier.fromValue(json['tier'] as String?),
      endsAt: endsAt == null ? null : DateTime.parse(endsAt),
      verified: json['verified'] as bool? ?? false,
      jobsThisMonth: (json['jobs_this_month'] as num?)?.toInt() ?? 0,
      monthlyJobLimit: (json['monthly_job_limit'] as num?)?.toInt(),
    );
  }
}
