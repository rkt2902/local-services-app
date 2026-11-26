/// Um tipo de combustível da tabela `fuel_types` (migration 0084). A lista
/// vem sempre da BD; para tirar um tipo, desativa-se lá.
class FuelType {
  const FuelType({
    required this.id,
    required this.name,
    this.isOil = false,
  });

  final String id;
  final String name;

  /// `icon = 'drop'` na BD: os óleos levam uma gota em vez da bomba.
  final bool isOil;

  factory FuelType.fromJson(Map<String, dynamic> json) => FuelType(
        id: json['id'] as String,
        name: json['name'] as String,
        isOil: json['icon'] == 'drop',
      );
}

/// Litros por mês de um tipo, como o Profissional os declarou.
class FuelUsageEntry {
  const FuelUsageEntry({
    required this.fuelTypeId,
    required this.litersPerMonth,
  });

  final String fuelTypeId;
  final double litersPerMonth;

  factory FuelUsageEntry.fromJson(Map<String, dynamic> json) => FuelUsageEntry(
        fuelTypeId: json['fuel_type_id'] as String,
        litersPerMonth: (json['liters_per_month'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'fuel_type_id': fuelTypeId,
        'liters_per_month': litersPerMonth,
      };
}
