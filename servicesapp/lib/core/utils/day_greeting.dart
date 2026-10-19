/// "Bom dia" até ao meio-dia, "Boa tarde" até às 20h, depois "Boa noite"
/// (e de madrugada, antes das 5h).
String dayGreeting(DateTime now) {
  final hour = now.hour;
  if (hour >= 5 && hour < 12) return 'Bom dia';
  if (hour >= 12 && hour < 20) return 'Boa tarde';
  return 'Boa noite';
}
