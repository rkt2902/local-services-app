import '../../../core/constants/enums.dart';

class HelpRequestSummary {
  final String id;
  final String jobId;
  final String proposalId;
  final int slotsNeeded;
  final HelpRequestStatus status;
  final bool equipmentRequired;
  final bool createdPostConfirmation;
  final DateTime createdAt;
  final double locationLat;
  final double locationLng;
  final String serviceTypeId;
  final String principalName;

  const HelpRequestSummary({
    required this.id,
    required this.jobId,
    required this.proposalId,
    required this.slotsNeeded,
    required this.status,
    required this.equipmentRequired,
    required this.createdPostConfirmation,
    required this.createdAt,
    required this.locationLat,
    required this.locationLng,
    required this.serviceTypeId,
    required this.principalName,
  });

  factory HelpRequestSummary.fromJson(Map<String, dynamic> json) =>
      HelpRequestSummary(
        id: json['id'] as String,
        jobId: json['job_id'] as String,
        proposalId: json['proposal_id'] as String,
        slotsNeeded: json['slots_needed'] as int,
        status: HelpRequestStatus.fromValue(json['status'] as String),
        equipmentRequired: json['equipment_required'] as bool,
        createdPostConfirmation: json['created_post_confirmation'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
        locationLat: (json['location_lat'] as num).toDouble(),
        locationLng: (json['location_lng'] as num).toDouble(),
        serviceTypeId: json['service_type_id'] as String,
        principalName: json['principal_name'] as String? ?? '',
      );
}

class HelpRequest {
  final String id;
  final String jobId;
  final String proposalId;
  final int slotsNeeded;
  final HelpRequestStatus status;
  final bool equipmentRequired;
  final bool createdPostConfirmation;
  final DateTime createdAt;

  const HelpRequest({
    required this.id,
    required this.jobId,
    required this.proposalId,
    required this.slotsNeeded,
    required this.status,
    required this.equipmentRequired,
    required this.createdPostConfirmation,
    required this.createdAt,
  });

  factory HelpRequest.fromJson(Map<String, dynamic> json) => HelpRequest(
        id: json['id'] as String,
        jobId: json['job_id'] as String,
        proposalId: json['proposal_id'] as String,
        slotsNeeded: json['slots_needed'] as int,
        status: HelpRequestStatus.fromValue(json['status'] as String),
        equipmentRequired: json['equipment_required'] as bool,
        createdPostConfirmation: json['created_post_confirmation'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  HelpRequest copyWith({
    String? id,
    String? jobId,
    String? proposalId,
    int? slotsNeeded,
    HelpRequestStatus? status,
    bool? equipmentRequired,
    bool? createdPostConfirmation,
    DateTime? createdAt,
  }) =>
      HelpRequest(
        id: id ?? this.id,
        jobId: jobId ?? this.jobId,
        proposalId: proposalId ?? this.proposalId,
        slotsNeeded: slotsNeeded ?? this.slotsNeeded,
        status: status ?? this.status,
        equipmentRequired: equipmentRequired ?? this.equipmentRequired,
        createdPostConfirmation:
            createdPostConfirmation ?? this.createdPostConfirmation,
        createdAt: createdAt ?? this.createdAt,
      );
}

class HelpAcceptanceSummary {
  final String id;
  final String helpRequestId;
  final HelpAcceptanceStatus status;
  final double agreedRate;
  final bool broughtEquipment;
  final DateTime createdAt;
  final String serviceTypeName;
  final String principalName;
  final String jobStatus;

  const HelpAcceptanceSummary({
    required this.id,
    required this.helpRequestId,
    required this.status,
    required this.agreedRate,
    required this.broughtEquipment,
    required this.createdAt,
    required this.serviceTypeName,
    required this.principalName,
    required this.jobStatus,
  });

  factory HelpAcceptanceSummary.fromJson(Map<String, dynamic> json) =>
      HelpAcceptanceSummary(
        id: json['id'] as String,
        helpRequestId: json['help_request_id'] as String,
        status: HelpAcceptanceStatus.fromValue(json['status'] as String),
        agreedRate: (json['agreed_rate'] as num).toDouble(),
        broughtEquipment: json['brought_equipment'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
        serviceTypeName: json['service_type_name'] as String? ?? '—',
        principalName: json['principal_name'] as String? ?? '—',
        jobStatus: json['job_status'] as String? ?? '',
      );
}

class HelpAcceptance {
  final String id;
  final String helpRequestId;
  final String workerId;
  final HelpAcceptanceStatus status;
  final double agreedRate;
  final bool broughtEquipment;
  final DateTime createdAt;

  const HelpAcceptance({
    required this.id,
    required this.helpRequestId,
    required this.workerId,
    required this.status,
    required this.agreedRate,
    required this.broughtEquipment,
    required this.createdAt,
  });

  factory HelpAcceptance.fromJson(Map<String, dynamic> json) => HelpAcceptance(
        id: json['id'] as String,
        helpRequestId: json['help_request_id'] as String,
        workerId: json['worker_id'] as String,
        status: HelpAcceptanceStatus.fromValue(json['status'] as String),
        agreedRate: (json['agreed_rate'] as num).toDouble(),
        broughtEquipment: json['brought_equipment'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
