/// Escala de espaçamento do design (2026-10-19):
/// 4 · 6 · 8 · 10 · 12 · 14 · 16 · 18 · 20 · 22 · 24 · 26 · 28 · 32.
///
/// Os nomes por tamanho (xxs a xl) são os passos principais e continuam a
/// ser a primeira escolha. Os intermédios (s6, s10, ...) existem porque o
/// design os usa em ecrãs concretos (auth, setup, folhas); são tokens, não
/// valores soltos.
abstract final class AppSpacing {
  const AppSpacing._();
  static const double xxs = 4.0;
  static const double s6 = 6.0;
  static const double xs = 8.0;
  static const double s10 = 10.0;
  static const double sm = 12.0;
  static const double s14 = 14.0;
  static const double md = 16.0;
  static const double s18 = 18.0;
  static const double s20 = 20.0;
  static const double s22 = 22.0;
  static const double lg = 24.0;
  static const double s26 = 26.0;
  static const double s28 = 28.0;
  static const double xl = 32.0;
}
