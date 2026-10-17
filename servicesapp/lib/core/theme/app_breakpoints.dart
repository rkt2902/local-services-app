/// Larguras de ecrã para a versão web, tablet e PC. Os designs são todos
/// mobile, por isso o conteúdo nunca cresce para lá de [contentMaxWidth]:
/// em ecrãs largos fica centrado, com o fundo da app dos dois lados.
abstract final class AppBreakpoints {
  const AppBreakpoints._();

  /// A partir desta largura (tablet deitado, PC) a bottom nav dá lugar a
  /// uma navegação lateral (NavigationRail).
  static const double expanded = 840.0;

  /// Lado menor mínimo para a navegação lateral: abaixo disto é um
  /// telemóvel (mesmo deitado) e fica a bottom nav.
  static const double compactShortestSide = 600.0;

  /// Largura máxima de qualquer ecrã.
  static const double contentMaxWidth = 640.0;
}
