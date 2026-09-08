import '../../../core/constants/enums.dart';

/// Uma linha de `worker_fleet_cards` (migration 0037). Um worker pode ter
/// mais que uma ao longo do tempo (tentativas rejeitadas + a atual) — ver
/// `FleetCardRepository.fetchMyFleetCard`, que devolve sempre a mais
/// recente.
class FleetCard {
  const FleetCard({
    required this.id,
    required this.workerId,
    this.cardNumber,
    required this.barcodeValue,
    this.holderName,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String workerId;
  final String? cardNumber;
  final String barcodeValue;
  final String? holderName;
  final FleetCardStatus status;
  final DateTime createdAt;

  factory FleetCard.fromJson(Map<String, dynamic> json) => FleetCard(
        id: json['id'] as String,
        workerId: json['worker_id'] as String,
        cardNumber: json['card_number'] as String?,
        barcodeValue: json['barcode_value'] as String,
        holderName: json['holder_name'] as String?,
        status: FleetCardStatus.fromValue(json['status'] as String?),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
