import '../../../core/constants/enums.dart';

class JobProposal {
  final String id;
  final String jobId;
  final String workerId;
  final double hourlyRate;
  final double estimatedHours;
  final int peopleNeeded;
  final String? notes;
  final ProposalStatus status;
  final DateTime createdAt;

  const JobProposal({
    required this.id,
    required this.jobId,
    required this.workerId,
    required this.hourlyRate,
    required this.estimatedHours,
    required this.peopleNeeded,
    this.notes,
    required this.status,
    required this.createdAt,
  });

  factory JobProposal.fromJson(Map<String, dynamic> json) => JobProposal(
        id: json['id'] as String,
        jobId: json['job_id'] as String,
        workerId: json['worker_id'] as String,
        hourlyRate: (json['hourly_rate'] as num).toDouble(),
        estimatedHours: (json['estimated_hours'] as num).toDouble(),
        peopleNeeded: (json['people_needed'] as num).toInt(),
        notes: json['notes'] as String?,
        status: ProposalStatus.fromString(json['status'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
