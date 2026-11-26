import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/worker/application/fuel_usage_form.dart';
import 'package:servicesapp/features/worker/data/fuel_usage_model.dart';

void main() {
  const types = [
    FuelType(id: 'diesel', name: 'Gasóleo'),
    FuelType(id: 'oil_2t', name: 'Óleo 2 tempos', isOil: true),
  ];

  group('parseFuelLiters', () {
    test('aceita vírgula e ponto', () {
      expect(parseFuelLiters('60'), 60);
      expect(parseFuelLiters('4,5'), 4.5);
      expect(parseFuelLiters(' 4.5 '), 4.5);
    });
    test('recusa vazio, zero e acima do limite', () {
      expect(parseFuelLiters(''), isNull);
      expect(parseFuelLiters('0'), isNull);
      expect(parseFuelLiters('10001'), isNull);
      expect(parseFuelLiters('abc'), isNull);
    });
  });

  group('fuelUsageMissingLabel', () {
    test('linhas vazias não bloqueiam (passo opcional)', () {
      expect(fuelUsageMissingLabel([FuelUsageRow(key: 0)], types), isNull);
    });
    test('litros sem combustível', () {
      expect(
        fuelUsageMissingLabel([FuelUsageRow(key: 0, litersText: '20')], types),
        'Falta escolher o combustível.',
      );
    });
    test('combustível sem litros diz qual', () {
      expect(
        fuelUsageMissingLabel(
            [FuelUsageRow(key: 0, fuelTypeId: 'diesel')], types),
        'Faltam os litros de Gasóleo.',
      );
    });
    test('litros inválidos', () {
      expect(
        fuelUsageMissingLabel(
            [FuelUsageRow(key: 0, fuelTypeId: 'oil_2t', litersText: '0')],
            types),
        contains('Óleo 2 tempos'),
      );
    });
  });

  test('fuelUsageEntries deixa de fora as linhas vazias', () {
    final entries = fuelUsageEntries([
      FuelUsageRow(key: 0, fuelTypeId: 'diesel', litersText: '120'),
      FuelUsageRow(key: 1),
      FuelUsageRow(key: 2, fuelTypeId: 'oil_2t', litersText: '2,5'),
    ]);
    expect(entries.map((e) => e.toJson()).toList(), [
      {'fuel_type_id': 'diesel', 'liters_per_month': 120.0},
      {'fuel_type_id': 'oil_2t', 'liters_per_month': 2.5},
    ]);
  });

  test('fuelLitersText mostra o valor como se escreve', () {
    expect(fuelLitersText(80), '80');
    expect(fuelLitersText(4.3), '4,3');
  });
}
