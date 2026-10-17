/// Valor de uma proposta aceite: preço por hora e, quando há estimativa de
/// horas, o intervalo total. Ex.: "25,00 €/h · ≈ 50 a 100 €".
///
/// Usado nos ecrãs de trabalho confirmado dos dois lados, para nunca
/// mostrar "a combinar" depois de o cliente já ter aceite um valor.
String agreedPriceLabel(double hourlyRate, double? hoursMin, double? hoursMax) {
  if (hourlyRate <= 0) return 'Preço a definir';
  final rate = '${hourlyRate.toStringAsFixed(2).replaceAll('.', ',')} €/h';
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
