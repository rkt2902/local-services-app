/// Custo de cada ajudante sobre o preço por hora do responsável, nas
/// estimativas: com equipamento próprio a hora inteira, sem equipamento 75%
/// (o ajudante recebe 70%; a margem é de propósito, ver decisions_log
/// "Factor de estimativa 0.75 vs pagamento real 0.70").
const double helperWithoutEquipmentFactor = 0.75;

/// Preço por hora da equipa toda: o do responsável mais cada ajudante
/// ([peopleNeeded] conta com o responsável). É a base de todos os totais
/// estimados da app, para o valor ser o mesmo em todos os ecrãs.
double teamHourlyRate(
  double hourlyRate, {
  int peopleNeeded = 1,
  bool helpersEquipmentRequired = false,
}) {
  final helpers = (peopleNeeded - 1).clamp(0, 99);
  final factor = helpersEquipmentRequired ? 1.0 : helperWithoutEquipmentFactor;
  return hourlyRate * (1 + helpers * factor);
}

/// Valor de uma proposta aceite: preço por hora e, quando há estimativa de
/// horas, o intervalo total com a equipa incluída. Ex.: "25,00 €/h · ≈ 50 a
/// 100 €".
///
/// Usado nos ecrãs de trabalho confirmado dos dois lados, para nunca
/// mostrar "a combinar" depois de o cliente já ter aceite um valor.
String agreedPriceLabel(
  double hourlyRate,
  double? hoursMin,
  double? hoursMax, {
  int peopleNeeded = 1,
  bool helpersEquipmentRequired = false,
}) {
  if (hourlyRate <= 0) return 'Preço a definir';
  final rate = hourlyRateLabel(hourlyRate);
  final total = estimatedTotalLabel(
    hourlyRate,
    hoursMin,
    hoursMax,
    peopleNeeded: peopleNeeded,
    helpersEquipmentRequired: helpersEquipmentRequired,
  );
  return total.isEmpty ? rate : '$rate · $total';
}

/// Só o intervalo total estimado ("≈ 50 a 100 €"), com a equipa incluída
/// ([teamHourlyRate]), ou vazio sem horas.
String estimatedTotalLabel(
  double hourlyRate,
  double? hoursMin,
  double? hoursMax, {
  int peopleNeeded = 1,
  bool helpersEquipmentRequired = false,
}) {
  if (hourlyRate <= 0) return '';
  final perHour = teamHourlyRate(
    hourlyRate,
    peopleNeeded: peopleNeeded,
    helpersEquipmentRequired: helpersEquipmentRequired,
  );
  String euros(double hours) => (perHour * hours).round().toString();
  if (hoursMin != null && hoursMax != null && hoursMax > hoursMin) {
    return '≈ ${euros(hoursMin)} a ${euros(hoursMax)} €';
  }
  final hours = hoursMin ?? hoursMax;
  if (hours == null) return '';
  return '≈ ${euros(hours)} €';
}

/// Número com vírgula decimal (pt-PT). Ex.: `decimalLabel(4.5, 1)` → "4,5".
String decimalLabel(double value, int fractionDigits) =>
    value.toStringAsFixed(fractionDigits).replaceAll('.', ',');

/// Preço por hora. Ex.: "25,00 €/h"; sem valor → "Preço a definir".
String hourlyRateLabel(double hourlyRate) {
  if (hourlyRate <= 0) return 'Preço a definir';
  return '${decimalLabel(hourlyRate, 2)} €/h';
}

/// Horas estimadas de uma proposta. Ex.: "1,5 - 3,0 h", "2,0 h" ou vazio.
String estimatedHoursLabel(double? hoursMin, double? hoursMax) {
  if (hoursMin != null && hoursMax != null) {
    return '${decimalLabel(hoursMin, 1)} - ${decimalLabel(hoursMax, 1)} h';
  }
  final hours = hoursMin ?? hoursMax;
  if (hours == null) return '';
  return '${decimalLabel(hours, 1)} h';
}

/// Valor em euros com vírgula decimal. Ex.: `moneyLabel(12.5)` → "12,50 €",
/// `moneyLabel(80, fractionDigits: 0)` → "80 €".
String moneyLabel(double value, {int fractionDigits = 2}) =>
    '${decimalLabel(value, fractionDigits)} €';

/// Distância curta para cartões. Ex.: "850 m", "4,2 km".
String distanceLabel(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${decimalLabel(meters / 1000, 1)} km';
