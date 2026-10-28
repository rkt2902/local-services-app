import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/constants/enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_brand_badge.dart';
import '../../../../core/widgets/app_initials_avatar.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_profile_card.dart';
import '../../../../core/widgets/app_plan_badge.dart';
import '../../../../core/widgets/app_tab_header.dart';
import '../../../../core/widgets/bottom_actions_bar.dart';
import '../../../../core/widgets/primary_action_button.dart';

class WorkerShareCardViewData {
  const WorkerShareCardViewData({
    required this.name,
    required this.professionLocationLabel,
    required this.qrUrl,
    required this.displayUrl,
    required this.planTier,
    required this.canExportPdf,
    this.ratingLabel,
    this.avatarUrl,
  });

  final String name;

  /// "Corte de relva · Braga".
  final String professionLocationLabel;

  /// "4,9 ★ · 38 avaliações"; `null` sem avaliações.
  final String? ratingLabel;
  final String? avatarUrl;

  /// Endereço no QR (`?src=qr`) e o que aparece escrito por baixo.
  final String qrUrl;
  final String displayUrl;
  final WorkerPlanTier planTier;

  /// PDF só no Pro e no Pro+; no Grátis o botão abre a folha do plano.
  final bool canExportPdf;
}

/// Ecrã do cartão partilhável: o cartão desenhado (o mesmo que vai na
/// imagem e no PDF) e as quatro formas de o partilhar. Sem Riverpod: a
/// integração passa os dados e as ações.
class WorkerShareCardView extends StatelessWidget {
  const WorkerShareCardView({
    super.key,
    required this.data,
    required this.cardKey,
    required this.busy,
    required this.onBack,
    required this.onShareImage,
    required this.onSavePdf,
    required this.onSendLink,
    required this.onCopyLink,
  });

  final WorkerShareCardViewData data;

  /// Chave do `RepaintBoundary` à volta do cartão, para o exportar.
  final GlobalKey cardKey;

  /// A gerar a imagem ou o PDF.
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onShareImage;
  final VoidCallback onSavePdf;
  final VoidCallback onSendLink;
  final VoidCallback onCopyLink;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBackHeader(
              title: 'O meu cartão',
              subtitle: 'Quem ler o QR abre o teu perfil e pede-te um orçamento',
              onBack: onBack,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    AppStaggeredEntrance(
                      index: 0,
                      child: Center(
                        child: RepaintBoundary(
                          key: cardKey,
                          child: WorkerShareCard(data: data),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 1,
                      child: Row(
                        children: [
                          Expanded(
                            child: _SecondaryAction(
                              icon: Icons.picture_as_pdf_outlined,
                              label: 'Guardar PDF',
                              trailing: data.canExportPdf
                                  ? null
                                  : const AppPlanBadge(tier: WorkerPlanTier.pro),
                              onPressed: busy ? null : onSavePdf,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: _SecondaryAction(
                              icon: Icons.link_rounded,
                              label: 'Copiar link',
                              onPressed: onCopyLink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: 2,
                      child: SizedBox(
                        width: double.infinity,
                        child: _SecondaryAction(
                          icon: Icons.send_outlined,
                          label: 'Enviar só o link',
                          onPressed: onSendLink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            BottomActionsBar(
              children: [
                PrimaryActionButton(
                  label: 'Partilhar cartão',
                  icon: Icons.ios_share_rounded,
                  isLoading: busy,
                  onPressed: busy ? null : onShareImage,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// O cartão em si. Largura fixa para a imagem e o PDF saírem sempre iguais,
/// em qualquer ecrã.
class WorkerShareCard extends StatelessWidget {
  const WorkerShareCard({super.key, required this.data});

  final WorkerShareCardViewData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final rating = data.ratingLabel;
    return Container(
      width: AppSizes.shareCardWidth,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.primary,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                const AppBrandBadge(
                  size: AppSizes.rowIconBox,
                  iconSize: AppSizes.rowIcon,
                  backgroundColor: AppColors.surface,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'ProJardim',
                  style: textTheme.titleMedium?.copyWith(
                    color: AppColors.surface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                AppInitialsAvatar(
                  initial: AppProfileCard.initialsOf(data.name),
                  radius: AppSizes.shareCardAvatarRadius,
                  avatarUrl: data.avatarUrl,
                  textStyle: textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    Text(
                      data.name,
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (data.planTier.isPaid)
                      AppPlanBadge(tier: data.planTier, large: true),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  data.professionLocationLabel,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                if (rating != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: AppSizes.inlineIcon,
                        color: AppColors.logoAccent,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        rating,
                        style: textTheme.bodyMedium
                            ?.copyWith(color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                QrImageView(
                  data: data.qrUrl,
                  size: AppSizes.shareCardQr,
                  padding: EdgeInsets.zero,
                  backgroundColor: AppColors.surface,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: AppColors.textPrimary,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Pede-me um orçamento',
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  data.displayUrl,
                  textAlign: TextAlign.center,
                  style: textTheme.labelSmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(0, AppSizes.compactButtonHeight),
        side: const BorderSide(color: AppColors.divider),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSizes.emphasisIcon),
          const SizedBox(width: AppSpacing.xs),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.xs),
            trailing!,
          ],
        ],
      ),
    );
  }
}
