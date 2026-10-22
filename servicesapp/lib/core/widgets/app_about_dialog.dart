import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_sizes.dart';
import '../theme/app_spacing.dart';
import 'app_legal_links.dart';
import 'app_motion.dart';
import 'primary_action_button.dart';

/// Versão mostrada em "Sobre a ProJardim" (igual ao `version` do pubspec).
const appVersionLabel = '1.0.0';

/// "Sobre a ProJardim", partilhado pela conta do cliente e do jardineiro.
/// Substitui o `showAboutDialog` do Material (em inglês, sem o logo e com o
/// fundo esverdeado do tema): logo, versão, o que é a app, Termos,
/// Privacidade e as licenças de software.
Future<void> showAppAboutDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => AppAboutDialog(
      onClose: () => Navigator.pop(dialogCtx),
      onTerms: () => openTermsOfUse(dialogCtx),
      onPrivacy: () => openPrivacyPolicy(dialogCtx),
      onLicenses: () => showLicensePage(
        context: dialogCtx,
        applicationName: 'ProJardim',
        applicationVersion: appVersionLabel,
        applicationIcon: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Image.asset(
            'assets/branding/app_icon_rounded.png',
            width: AppSizes.dialogIconBox,
            height: AppSizes.dialogIconBox,
          ),
        ),
      ),
    ),
  );
}

class AppAboutDialog extends StatelessWidget {
  const AppAboutDialog({
    super.key,
    required this.onClose,
    required this.onTerms,
    required this.onPrivacy,
    required this.onLicenses,
  });

  final VoidCallback onClose;
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;
  final VoidCallback onLicenses;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.dialogMaxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppStaggeredEntrance(
                index: 0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: Image.asset(
                    'assets/branding/app_icon_rounded.png',
                    width: AppSizes.aboutLogo,
                    height: AppSizes.aboutLogo,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppStaggeredEntrance(
                index: 1,
                child: Column(
                  children: [
                    Text(
                      'ProJardim',
                      style: textTheme.headlineSmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        'Versão $appVersionLabel',
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.primaryPressed,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppStaggeredEntrance(
                index: 2,
                child: Text(
                  'Liga quem precisa de um jardim cuidado a jardineiros da '
                  'sua zona. Pedes, recebes propostas, escolhes e falas '
                  'pelo WhatsApp.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppStaggeredEntrance(
                index: 3,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.input),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    children: [
                      _AboutLink(
                        icon: Icons.description_outlined,
                        label: 'Termos de utilização',
                        onTap: onTerms,
                      ),
                      const Divider(height: 1, color: AppColors.divider),
                      _AboutLink(
                        icon: Icons.privacy_tip_outlined,
                        label: 'Política de privacidade',
                        onTap: onPrivacy,
                      ),
                      const Divider(height: 1, color: AppColors.divider),
                      _AboutLink(
                        icon: Icons.code_rounded,
                        label: 'Licenças de software',
                        onTap: onLicenses,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppStaggeredEntrance(
                index: 4,
                child: PrimaryActionButton(label: 'Fechar', onPressed: onClose),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutLink extends StatelessWidget {
  const _AboutLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(icon, size: AppSizes.infoRowIcon, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textPrimary),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
