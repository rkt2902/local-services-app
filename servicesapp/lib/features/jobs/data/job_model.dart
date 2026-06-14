import '../../../core/constants/enums.dart';

class JobRequest {
  final String id;
  final String clientId;
  final String serviceTypeId;
  final String addressText;
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

  const JobRequest({
    required this.id,
    required this.clientId,
    required this.serviceTypeId,
    required this.addressText,
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
  });

  factory JobRequest.fromJson(Map<String, dynamic> json) => JobRequest(
        id: json['id'] as String,
        clientId: json['client_id'] as String,
        serviceTypeId: json['service_type_id'] as String,
        addressText: json['address_text'] as String,
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
      );

  JobRequest copyWith({
    String? id,
    String? clientId,
    String? serviceTypeId,
    String? addressText,
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
  }) =>
      JobRequest(
        id: id ?? this.id,
        clientId: clientId ?? this.clientId,
        serviceTypeId: serviceTypeId ?? this.serviceTypeId,
        addressText: addressText ?? this.addressText,
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
      );
}
