import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';
import 'package:servicesapp/core/widgets/app_account_menu_group.dart';
import 'package:servicesapp/core/widgets/app_motion.dart';
import 'package:servicesapp/core/widgets/app_profile_card.dart';
import 'package:servicesapp/core/widgets/app_tab_header.dart';

class ClientAccountViewData {
  const ClientAccountViewData({
    required this.name,
    required this.subtitle,
    required this.totalJobs,
    required this.activeJobs,
    required this.completedJobs,
    required this.ratingLabel,
    required this.reviewsLabel,
    this.avatarUrl,
  });

  final String name;
  final String? avatarUrl;

  /// Ex.: "Cliente desde 2024".
  final String subtitle;

  final int totalJobs;
  final int activeJobs;
  final int completedJobs;

  /// Avaliações que o cliente RECEBEU (dos workers), mesmo par de campos
  /// já usado em `WorkerAccountViewData` (`ratingSummaryProvider` serve os
  /// dois papéis — ver `MyRatingsRoute`).
  final String ratingLabel;
  final String reviewsLabel;
}

/// Perfil do cliente (design A11, C4). Mesma estrutura do Perfil do
/// jardineiro: cartão com números, atalhos e conta. Sem cartão partilhável.
class ClientAccountScreen extends StatelessWidget {
  const ClientAccountScreen({
    required this.data,
    required this.onSettingsPressed,
    required this.onJobsPressed,
    required this.onReviewsPressed,
    required this.onNotificationsPressed,
    required this.onSupportPressed,
    required this.onAboutPressed,
    required this.onSignOutPressed,
    required this.onDeleteAccountPressed,
    super.key,
  });

  final ClientAccountViewData data;

  /// Roda dentada e toque no nome: editar o perfil.
  final VoidCallback onSettingsPressed;
  final VoidCallback onJobsPressed;
  final VoidCallback onReviewsPressed;
  final VoidCallback onNotificationsPressed;
  final VoidCallback onSupportPressed;
  final VoidCallback onAboutPressed;
  final VoidCallback onSignOutPressed;
  final VoidCallback onDeleteAccountPressed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTabHeader(
              title: 'Perfil',
              actions: [
                IconButton(
                  onPressed: onSettingsPressed,
                  tooltip: 'Definições',
                  icon: const Icon(
                    Icons.settings_outlined,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.xl,
                ),
                child: Column(
                  children: [
                    AppStaggeredEntrance(
                      index: 0,
                      child: AppProfileCard(
                        name: data.name,
                        subtitle: data.subtitle,
                        avatarUrl: data.avatarUrl,
                        onPressed: onSettingsPressed,
                        metrics: [
                          AppProfileMetric(
                            value: '${data.totalJobs}',
                            label: 'Pedidos',
                          ),
                          AppProfileMetric(
                            value: '${data.activeJobs}',
                            label: 'Em curso',
                          ),
                          AppProfileMetric(
                            value: '${data.completedJobs}',
                            label: 'Concluídos',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
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
                            label: 'As minhas avaliações',
                            icon: Icons.star_border_rounded,
                            trailingLabel: data.ratingLabel == '—'
                                ? data.reviewsLabel
                                : '${data.ratingLabel} · ${data.reviewsLabel}',
                          ),
                          const AppAccountMenuItem(
                            id: 'notifications',
                            label: 'Notificações',
                            icon: Icons.notifications_none_rounded,
                          ),
                        ],
                        onItemPressed: (id) {
                          switch (id) {
                            case 'jobs':
                              onJobsPressed();
                            case 'reviews':
                              onReviewsPressed();
                            case 'notifications':
                              onNotificationsPressed();
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(
                      index: 2,
                      child: AppAccountMenuGroup(
                        items: const [
                          AppAccountMenuItem(
                            id: 'support',
                            label: 'Contacto e suporte',
                            icon: Icons.support_agent_outlined,
                          ),
                          AppAccountMenuItem(
                            id: 'about',
                            label: 'Sobre a ProJardim',
                            icon: Icons.info_outline_rounded,
                          ),
                          AppAccountMenuItem(
                            id: 'sign_out',
                            label: 'Terminar sessão',
                            icon: Icons.logout_rounded,
                            destructive: true,
                          ),
                        ],
                        onItemPressed: (id) {
                          switch (id) {
                            case 'support':
                              onSupportPressed();
                            case 'about':
                              onAboutPressed();
                            case 'sign_out':
                              onSignOutPressed();
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(
                      index: 3,
                      child: AppAccountMenuGroup(
                        items: const [
                          AppAccountMenuItem(
                            id: 'delete_account',
                            label: 'Eliminar conta',
                            icon: Icons.delete_outline_rounded,
                            destructive: true,
                          ),
                        ],
                        onItemPressed: (_) => onDeleteAccountPressed(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
