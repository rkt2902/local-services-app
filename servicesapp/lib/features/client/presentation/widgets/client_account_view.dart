import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_sizes.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';
import 'package:servicesapp/core/widgets/app_account_menu_group.dart';
import 'package:servicesapp/core/widgets/app_motion.dart';

class ClientAccountViewData {
  const ClientAccountViewData({
    required this.name,
    required this.totalJobs,
    required this.ratingLabel,
    required this.reviewsLabel,
    this.avatarImage,
  });

  final String name;
  final ImageProvider? avatarImage;

  final int totalJobs;

  /// Avaliações que o cliente RECEBEU (dos workers), mesmo par de campos
  /// já usado em `WorkerAccountViewData` (`ratingSummaryProvider` serve os
  /// dois papéis — ver `MyRatingsRoute`).
  final String ratingLabel;
  final String reviewsLabel;
}

class ClientAccountScreen extends StatelessWidget {
  const ClientAccountScreen({
    required this.data,
    required this.onSettingsPressed,
    required this.onJobsPressed,
    required this.onReviewsPressed,
    required this.onDefinitionsPressed,
    required this.onSupportPressed,
    required this.onAboutPressed,
    required this.onTermsPressed,
    required this.onPrivacyPressed,
    required this.onSignOutPressed,
    required this.onDeleteAccountPressed,
    super.key,
  });

  final ClientAccountViewData data;

  final VoidCallback onSettingsPressed;
  final VoidCallback onJobsPressed;
  final VoidCallback onReviewsPressed;
  final VoidCallback onDefinitionsPressed;
  final VoidCallback onSupportPressed;
  final VoidCallback onAboutPressed;
  final VoidCallback onTermsPressed;
  final VoidCallback onPrivacyPressed;
  final VoidCallback onSignOutPressed;
  final VoidCallback onDeleteAccountPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        // Ao fazer scroll, uma sombra leve separa o título dos cartões que
        // passam por baixo, em vez de os cortar a seco.
        scrolledUnderElevation: AppSizes.scrolledHeaderElevation,
        shadowColor: AppColors.textPrimary.withValues(alpha: 0.12),
        titleSpacing: AppSpacing.lg,
        title: Text(
          'A minha conta',
          style: textTheme.displaySmall?.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          children: [
            AppStaggeredEntrance(
              index: 0,
              child: _ClientIdentityCard(
                data: data,
                onPressed: onSettingsPressed,
              ),
            ),
            const SizedBox(
              height: AppSpacing.md,
            ),
            AppStaggeredEntrance(
              index: 1,
              child: AppAccountMenuGroup(
                items: [
                  const AppAccountMenuItem(
                    id: 'jobs',
                    label: 'Os meus pedidos',
                    icon: Icons.receipt_long_outlined,
                  ),
                  AppAccountMenuItem(
                    id: 'reviews',
                    label: 'Avaliações',
                    icon: Icons.star_border_rounded,
                    trailingLabel: '${data.ratingLabel} · ${data.reviewsLabel}',
                  ),
                  const AppAccountMenuItem(
                    id: 'settings',
                    label: 'Definições',
                    icon: Icons.settings_outlined,
                  ),
                  const AppAccountMenuItem(
                    id: 'support',
                    label: 'Contacto e suporte',
                    icon: Icons.support_agent_outlined,
                  ),
                  const AppAccountMenuItem(
                    id: 'about',
                    label: 'Sobre a ProJardim',
                    icon: Icons.info_outline_rounded,
                  ),
                  const AppAccountMenuItem(
                    id: 'terms',
                    label: 'Termos de utilização',
                    icon: Icons.description_outlined,
                  ),
                  const AppAccountMenuItem(
                    id: 'privacy',
                    label: 'Política de Privacidade',
                    icon: Icons.privacy_tip_outlined,
                  ),
                ],
                onItemPressed: (id) {
                  switch (id) {
                    case 'jobs':
                      onJobsPressed();
                    case 'reviews':
                      onReviewsPressed();
                    case 'settings':
                      onDefinitionsPressed();
                    case 'support':
                      onSupportPressed();
                    case 'about':
                      onAboutPressed();
                    case 'terms':
                      onTermsPressed();
                    case 'privacy':
                      onPrivacyPressed();
                  }
                },
              ),
            ),
            const SizedBox(
              height: AppSpacing.md,
            ),
            AppStaggeredEntrance(
              index: 2,
              child: AppAccountMenuGroup(
                items: const [
                  AppAccountMenuItem(
                    id: 'sign_out',
                    label: 'Terminar sessão',
                    icon: Icons.logout_rounded,
                    destructive: true,
                  ),
                  AppAccountMenuItem(
                    id: 'delete_account',
                    label: 'Eliminar conta',
                    icon: Icons.delete_outline_rounded,
                    destructive: true,
                  ),
                ],
                onItemPressed: (id) {
                  switch (id) {
                    case 'sign_out':
                      onSignOutPressed();
                    case 'delete_account':
                      onDeleteAccountPressed();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientIdentityCard extends StatelessWidget {
  const _ClientIdentityCard({
    required this.data,
    required this.onPressed,
  });

  final ClientAccountViewData data;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final jobs = data.totalJobs;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: AppSizes.headerIconButton / 2,
                backgroundColor: AppColors.primaryContainer,
                backgroundImage: data.avatarImage,
                child: data.avatarImage == null
                    ? const Icon(
                        Icons.person_outline_rounded,
                        color: AppColors.primary,
                      )
                    : null,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Cliente · $jobs ${jobs == 1 ? 'pedido' : 'pedidos'}',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
