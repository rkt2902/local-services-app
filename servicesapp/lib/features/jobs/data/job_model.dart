import '../../../core/constants/enums.dart';

class JobRequest {
  final String id;
  final String clientId;
  final String serviceTypeId;
  final String addressText;
  final double locationLat;
  final double locationLng;
  final DateTime? preferredDate;
  final Urgency? urgency;
  final SizeEstimate? sizeEstimate;
  final String description;
  final JobStatus status;
  final String? acceptedProposalId;
  final DateTime expiresAt;
  final DateTime createdAt;

  const JobRequest({
    required this.id,
    required this.clientId,
    required this.serviceTypeId,
    required this.addressText,
    required this.locationLat,
    required this.locationLng,
    this.preferredDate,
    this.urgency,
    this.sizeEstimate,
    required this.description,
    required this.status,
    this.acceptedProposalId,
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
        preferredDate: json['preferred_date'] != null
            ? DateTime.parse(json['preferred_date'] as String)
            : null,
        urgency: json['urgency'] != null
            ? Urgency.fromString(json['urgency'] as String)
            : null,
        sizeEstimate: json['size_estimate'] != null
            ? SizeEstimate.fromString(json['size_estimate'] as String)
            : null,
        description: json['description'] as String,
        status: JobStatus.fromString(json['status'] as String),
        acceptedProposalId: json['accepted_proposal_id'] as String?,
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
    DateTime? preferredDate,
    Urgency? urgency,
    SizeEstimate? sizeEstimate,
    String? description,
    JobStatus? status,
    String? acceptedProposalId,
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
        preferredDate: preferredDate ?? this.preferredDate,
        urgency: urgency ?? this.urgency,
        sizeEstimate: sizeEstimate ?? this.sizeEstimate,
        description: description ?? this.description,
        status: status ?? this.status,
        acceptedProposalId: acceptedProposalId ?? this.acceptedProposalId,
        expiresAt: expiresAt ?? this.expiresAt,
        createdAt: createdAt ?? this.createdAt,
      );
}
