/// Tamanhos fixos dos componentes base (design U1, 2026-10-19): caixas de
/// ícone, alturas de botão e larguras máximas. Tal como [AppSpacing], são
/// tokens; os ecrãs não usam números soltos para isto.
abstract final class AppSizes {
  const AppSizes._();

  /// Altura mínima do [AppStatusBadge] normal.
  static const double badgeMinHeight = 28.0;

  /// Altura dos botões principais e dos de login social.
  static const double buttonHeight = 52.0;

  /// Logo do Google/Facebook dentro dos botões de login social.
  static const double socialLogo = 20.0;

  /// Botões lado a lado dentro de um diálogo ("Voltar" / "Confirmar").
  static const double compactButtonHeight = 48.0;

  /// Caixa com o ícone no topo do [AppConfirmDialog].
  static const double dialogIconBox = 48.0;
  static const double dialogIcon = 26.0;
  static const double dialogMaxWidth = 420.0;

  /// Círculo do [AppEmptyState].
  static const double emptyIconCircle = 68.0;
  static const double emptyIcon = 34.0;
  static const double emptyActionMinWidth = 180.0;
  static const double emptyActionMaxWidth = 280.0;

  /// Caixa do ícone nas linhas de lista ([NextStepRow], [TodoRow]).
  static const double rowIconBox = 40.0;
  static const double rowIcon = 22.0;

  /// Pega das folhas ([AppSheet]).
  static const double sheetHandleWidth = 40.0;
  static const double sheetHandleHeight = 4.0;

  /// Ponto verde antes do próximo passo de um pedido que precisa de ação.
  static const double statusDot = 6.0;
}
