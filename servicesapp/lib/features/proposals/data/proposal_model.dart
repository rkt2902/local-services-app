import '../../../core/constants/enums.dart';
import '../../../core/config/storage_urls.dart';

class JobProposal {
  final String id;
  final String jobId;
  final String workerId;

  /// No valor total é só uma hora de referência para a sugestão aos
  /// ajudantes (migration 0058); o cliente nunca a vê.
  final double hourlyRate;
  final double? estimatedHoursMin;
  final double? estimatedHoursMax;
  final int peopleNeeded;
  final String? notes;
  final ProposalStatus status;
  final DateTime? scheduledDate;
  final String? scheduledTime;
  final bool scheduledFlexible;
  final bool helpersEquipmentRequired;
  final DateTime createdAt;
  final String? workerName;
  final String? workerAvatarUrl;

  // Design A6 (migration 0058). Sem a migration vêm os valores por omissão.
  final ProposalPricingMode pricingMode;
  final double? totalPrice;

  /// Slugs de `proposal_include_options`.
  final List<String> includes;
  final int? estimatedDaysMin;
  final int? estimatedDaysMax;
  final DateTime? validUntil;

  /// Calculado no servidor (get_pending_proposals_for_job); nas leituras
  /// diretas da tabela vem sempre false.
  final bool isExpired;

  /// Plano de quem propôs, para o selo (get_pending_proposals_for_job,
  /// 0067). Grátis nas leituras diretas da tabela e antes da 0067.
  final WorkerPlanTier workerPlanTier;

  const JobProposal({
    required this.id,
    required this.jobId,
    required this.workerId,
    required this.hourlyRate,
    this.estimatedHoursMin,
    this.estimatedHoursMax,
    required this.peopleNeeded,
    this.notes,
    required this.status,
    this.scheduledDate,
    this.scheduledTime,
    this.scheduledFlexible = false,
    this.helpersEquipmentRequired = false,
    required this.createdAt,
    this.workerName,
    this.workerAvatarUrl,
    this.pricingMode = ProposalPricingMode.hourly,
    this.totalPrice,
    this.includes = const [],
    this.estimatedDaysMin,
    this.estimatedDaysMax,
    this.validUntil,
    this.isExpired = false,
    this.workerPlanTier = WorkerPlanTier.free,
  });

  bool get isFixedTotal =>
      pricingMode == ProposalPricingMode.fixedTotal &&
      (totalPrice ?? 0) > 0;

  factory JobProposal.fromJson(Map<String, dynamic> json) => JobProposal(
        id: json['id'] as String,
        jobId: json['job_id'] as String,
        workerId: json['worker_id'] as String,
        hourlyRate: (json['hourly_rate'] as num).toDouble(),
        estimatedHoursMin:
            (json['estimated_hours_min'] as num?)?.toDouble(),
        estimatedHoursMax:
            (json['estimated_hours_max'] as num?)?.toDouble(),
        peopleNeeded: (json['people_needed'] as num).toInt(),
        notes: json['notes'] as String?,
        status: ProposalStatus.fromString(json['status'] as String),
        scheduledDate: json['scheduled_date'] != null
            ? DateTime.parse(json['scheduled_date'] as String)
            : null,
        scheduledTime: json['scheduled_time'] as String?,
        scheduledFlexible: json['scheduled_flexible'] as bool? ?? false,
        helpersEquipmentRequired:
            json['helpers_equipment_required'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        // `worker_name`/`worker_avatar_url` — colunas planas da RPC
        // get_pending_proposals_for_job. `profiles.full_name`/`avatar_url`
        // mantido como fallback do embedded join antigo (hoje sem call sites).
        workerName: json['worker_name'] as String? ??
            (json['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
        workerAvatarUrl: StorageUrls.trustedOrNull(
            json['worker_avatar_url'] as String? ??
                (json['profiles'] as Map<String, dynamic>?)?['avatar_url']
                    as String?),
        pricingMode:
            ProposalPricingMode.fromString(json['pricing_mode'] as String?),
        totalPrice: (json['total_price'] as num?)?.toDouble(),
        includes: (json['includes'] as List?)?.cast<String>() ?? const [],
        estimatedDaysMin: (json['estimated_days_min'] as num?)?.toInt(),
        estimatedDaysMax: (json['estimated_days_max'] as num?)?.toInt(),
        validUntil: json['valid_until'] != null
            ? DateTime.parse(json['valid_until'] as String)
            : null,
        isExpired: json['is_expired'] as bool? ?? false,
        workerPlanTier:
            WorkerPlanTier.fromValue(json['worker_plan_tier'] as String?),
      );
}

/// Opção de "O que inclui" (tabela `proposal_include_options`, 0058).
class ProposalIncludeOption {
  const ProposalIncludeOption({required this.slug, required this.label});

  final String slug;
  final String label;

  factory ProposalIncludeOption.fromJson(Map<String, dynamic> json) =>
      ProposalIncludeOption(
        slug: json['slug'] as String,
        label: json['label'] as String,
      );
}

/// Um dia de trabalho (tabela `job_work_days`, 0058). `endedAt` null é o
/// dia em curso.
class JobWorkDay {
  const JobWorkDay({
    required this.dayNumber,
    required this.startedAt,
    this.endedAt,
  });

  final int dayNumber;
  final DateTime startedAt;
  final DateTime? endedAt;

  bool get isOpen => endedAt == null;

  factory JobWorkDay.fromJson(Map<String, dynamic> json) => JobWorkDay(
        dayNumber: (json['day_number'] as num).toInt(),
        startedAt: DateTime.parse(json['started_at'] as String),
        endedAt: json['ended_at'] != null
            ? DateTime.parse(json['ended_at'] as String)
            : null,
      );
}
