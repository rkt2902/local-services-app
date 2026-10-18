/// Valor de uma proposta aceite: preço por hora e, quando há estimativa de
/// horas, o intervalo total. Ex.: "25,00 €/h · ≈ 50 a 100 €".
///
/// Usado nos ecrãs de trabalho confirmado dos dois lados, para nunca
/// mostrar "a combinar" depois de o cliente já ter aceite um valor.
String agreedPriceLabel(double hourlyRate, double? hoursMin, double? hoursMax) {
  if (hourlyRate <= 0) return 'Preço a definir';
  final rate = hourlyRateLabel(hourlyRate);
  final total = estimatedTotalLabel(hourlyRate, hoursMin, hoursMax);
  return total.isEmpty ? rate : '$rate · $total';
}

/// Só o intervalo total estimado ("≈ 50 a 100 €"), ou vazio sem horas.
String estimatedTotalLabel(double hourlyRate, double? hoursMin, double? hoursMax) {
  if (hourlyRate <= 0) return '';
  String euros(double hours) => (hourlyRate * hours).toStringAsFixed(0);
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

/// Ordenação "Por preço" das propostas: total mínimo estimado
/// (preço/hora × horas mínimas) a subir. Propostas sem horas ficam depois
/// de todas as que têm horas (o total delas é desconhecido), ordenadas
/// entre si pelo preço por hora.
int compareByEstimatedPrice(
  ({double hourlyRate, double? hoursMin, double? hoursMax}) a,
  ({double hourlyRate, double? hoursMin, double? hoursMax}) b,
) {
  final aHours = a.hoursMin ?? a.hoursMax;
  final bHours = b.hoursMin ?? b.hoursMax;
  if (aHours == null && bHours == null) {
    return a.hourlyRate.compareTo(b.hourlyRate);
  }
  if (aHours == null) return 1;
  if (bHours == null) return -1;
  return (a.hourlyRate * aHours).compareTo(b.hourlyRate * bHours);
}
