import '../data/fuel_usage_model.dart';

/// Uma linha do formulário de combustível: tipo (ou nenhum ainda) e o texto
/// dos litros tal como foi escrito. `key` só serve para o Flutter não
/// trocar os campos quando se remove uma linha do meio.
class FuelUsageRow {
  FuelUsageRow({required this.key, this.fuelTypeId, this.litersText = ''});

  final int key;
  String? fuelTypeId;
  String litersText;

  bool get isEmpty => fuelTypeId == null && litersText.trim().isEmpty;
}

/// Limite da BD (CHECK em worker_fuel_usage).
const double fuelLitersMax = 10000;

/// "60", "60,5" ou "60.5" dão o número; vazio, zero, negativo ou acima do
/// limite dão `null`.
double? parseFuelLiters(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || value <= 0 || value > fuelLitersMax) return null;
  return value;
}

/// A primeira coisa que falta, para mostrar por cima do botão; `null` quando
/// se pode gravar. Linhas vazias não contam (o passo é opcional).
String? fuelUsageMissingLabel(
  List<FuelUsageRow> rows,
  List<FuelType> types,
) {
  for (final row in rows) {
    if (row.isEmpty) continue;
    if (row.fuelTypeId == null) return 'Falta escolher o combustível.';
    final name = types
        .where((t) => t.id == row.fuelTypeId)
        .map((t) => t.name)
        .firstOrNull;
    if (row.litersText.trim().isEmpty) {
      return 'Faltam os litros de ${name ?? 'um combustível'}.';
    }
    if (parseFuelLiters(row.litersText) == null) {
      return 'Os litros de ${name ?? 'um combustível'} têm de ser um '
          'número entre 1 e ${fuelLitersMax.toStringAsFixed(0)}.';
    }
  }
  return null;
}

/// As linhas completas, prontas para gravar (as vazias ficam de fora).
List<FuelUsageEntry> fuelUsageEntries(List<FuelUsageRow> rows) => [
      for (final row in rows)
        if (row.fuelTypeId != null && parseFuelLiters(row.litersText) != null)
          FuelUsageEntry(
            fuelTypeId: row.fuelTypeId!,
            litersPerMonth: parseFuelLiters(row.litersText)!,
          ),
    ];

/// Texto do campo a partir do valor gravado: "80" e não "80.0"; "4,3".
String fuelLitersText(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString().replaceAll('.', ',');
