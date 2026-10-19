/// Larguras de ecrã para a versão web, tablet e PC. Os designs são todos
/// mobile, por isso o conteúdo nunca cresce para lá de [contentMaxWidth]:
/// em ecrãs largos fica centrado, com o fundo da app dos dois lados.
abstract final class AppBreakpoints {
  const AppBreakpoints._();

  /// A partir desta largura (tablet deitado, PC) a bottom nav dá lugar a
  /// uma navegação lateral (NavigationRail).
  static const double expanded = 840.0;

  /// Lado menor mínimo para a navegação lateral: abaixo disto é um
  /// telemóvel (mesmo deitado) e fica a bottom nav (design U8).
  static const double compactShortestSide = 480.0;

  /// Largura máxima de qualquer ecrã (design U8). Detalhes e sub-ecrãs
  /// abrem nesta mesma coluna, nunca num segundo painel.
  static const double contentMaxWidth = 720.0;
}
