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

  /// Caixa do ícone nos cartões de atalho (folha do "+" do jardineiro).
  static const double actionIconBox = 44.0;

  /// Botão redondo das notificações no cabeçalho do Início.
  static const double headerIconButton = 44.0;
  static const double unreadDot = 9.0;

  /// Sombra do cabeçalho fixo quando o conteúdo passa por baixo
  /// (ex.: "A minha conta").
  static const double scrolledHeaderElevation = 2.0;

  /// Pega das folhas ([AppSheet]).
  static const double sheetHandleWidth = 40.0;
  static const double sheetHandleHeight = 4.0;

  /// Ponto verde antes do próximo passo de um pedido que precisa de ação.
  static const double statusDot = 6.0;

  // Pedido: passo 2 "Quando e onde" e "Editar pedido" (U3).
  static const double scheduleChoiceHeight = 40.0;
  static const double dateFieldMinHeight = 56.0;
  static const double attributeChipHeight = 38.0;
  static const double jobMapHeight = 164.0;
  static const double mapPin = 36.0;
  static const double inlineIcon = 18.0;

  /// Ícone de destaque num botão de 44 px ("Iniciar" da Agenda) e o visto
  /// de concluído na linha compacta.
  static const double emphasisIcon = 20.0;
  static const double inlineSpinner = 16.0;

  // Fluxo do ajudante e equipa (U4).
  static const double progressBarHeight = 8.0;
  static const double slotsValueWidth = 72.0;
  static const double ratingStar = 14.0;
  static const double metaIcon = 15.0;
  static const double avatarSmall = 38.0;

  // Autenticação: login, código do email e escolha de papel (U5).
  static const double authBrandBadge = 52.0;
  static const double authBrandIcon = 26.0;
  static const double authHeaderIcon = 56.0;
  static const double authHeaderGlyph = 28.0;

  // Perfil do jardineiro: destaques, redes e cartão público (U6).
  static const double linkButtonHeight = 44.0;
  static const double publicAvatar = 76.0;
  static const double reviewAvatar = 36.0;
  static const double socialFieldLabelWidth = 76.0;

  // Navegação lateral em tablet deitado e PC (U8).
  static const double railWidth = 92.0;
  static const double railAction = 52.0;
  static const double railBrand = 40.0;

  // Detalhe do trabalho do jardineiro (A1).
  static const double teamSlot = 32.0;

  /// Logo do ecrã de arranque (`/loading`), a seguir ao splash nativo.
  static const double launchLogo = 128.0;

  /// Logo no diálogo "Sobre a ProJardim".
  static const double aboutLogo = 72.0;
  static const double heroIcon = 28.0;
  static const double infoRowIcon = 20.0;

  // Propostas recebidas (A3).
  static const double proposalCardSkeleton = 164.0;

  // Notificações (A4).
  static const double notificationSkeletonLabel = 72.0;
  static const double notificationSkeletonSection = 168.0;

  // Pedido direto, "Pedir de novo" (A5).
  static const double directAvatarRadius = 18.0;
  static const double gardenerAvatarRadius = 22.0;
  static const double gardenerCardHeight = 164.0;
  static const double gardenerSkeletonTitleWidth = 164.0;
  static const double repeatHireSkeleton = 132.0;
  static const double directBannerSkeleton = 116.0;

  // Pedido pelo cartão público (A7).
  static const double directChipAvatarRadius = 14.0;
  static const double directServiceSkeleton = 76.0;
}
