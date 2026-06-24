import '../../../core/constants/enums.dart';

class JobProposal {
  final String id;
  final String jobId;
  final String workerId;
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
  });

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
      );
}
