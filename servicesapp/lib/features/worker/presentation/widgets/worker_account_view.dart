import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_sizes.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';
import 'package:servicesapp/core/widgets/app_account_menu_group.dart';
import 'package:servicesapp/core/widgets/app_motion.dart';
import 'package:servicesapp/core/widgets/app_profile_card.dart';
import 'package:servicesapp/core/widgets/app_tab_header.dart';

class WorkerAccountViewData {
  const WorkerAccountViewData({
    required this.name,
    required this.professionLocationLabel,
    required this.ratingLabel,
    required this.reviewsLabel,
    required this.completedJobsLabel,
    required this.memberSinceLabel,
    required this.fleetCardStatusLabel,
    required this.planLabel,
    this.canSharePublicCard = true,
    this.avatarUrl,
  });

  final String name;
  final String professionLocationLabel;

  /// "4,9" (ou "—" sem avaliações) e "128 avaliações".
  final String ratingLabel;
  final String reviewsLabel;

  /// Números do cartão, já formatados ("86", "2021"; "—" sem dados).
  final String completedJobsLabel;
  final String memberSinceLabel;

  /// Já formatado pela integração (`FleetCardStatus.presentation.label` —
  /// "Não pedido"/"Pendente"/"Ativo"/"Rejeitado"). Texto simples, não
  /// widget: `AppAccountMenuItem.trailingLabel` só aceita `String?`.
  final String fleetCardStatusLabel;

  /// "Grátis · 3 de 5 este mês", "Pro · até 22/10/2027" (ver
  /// `worker_plan_labels.dart`).
  final String planLabel;

  /// "Partilhar" e "QR" do cartão público (A11). Vem do plano
  /// (`can_use_public_card`); sem ele os botões não aparecem.
  final bool canSharePublicCard;

  final String? avatarUrl;
}

/// Perfil do jardineiro (design A11, J6): o mesmo cartão do Perfil do
/// cliente, mais o cartão partilhável e os atalhos de trabalho.
class WorkerAccountScreen extends StatelessWidget {
  const WorkerAccountScreen({
    required this.data,
    required this.onSettingsPressed,
    required this.onShareCardPressed,
    required this.onQrPressed,
    required this.onAgendaPressed,
    required this.onHelpRequestsPressed,
    required this.onReviewsPressed,
    required this.onFleetCardPressed,
    required this.onPlanPressed,
    required this.onNotificationsPressed,
    required this.onSupportPressed,
    required this.onAboutPressed,
    required this.onSignOutPressed,
    required this.onDeleteAccountPressed,
    super.key,
  });

  final WorkerAccountViewData data;

  /// Roda dentada e toque no nome: editar o perfil.
  final VoidCallback onSettingsPressed;
  final VoidCallback onShareCardPressed;
  final VoidCallback onQrPressed;

  final VoidCallback onAgendaPressed;
  final VoidCallback onHelpRequestsPressed;
  final VoidCallback onReviewsPressed;
  final VoidCallback onFleetCardPressed;
  final VoidCallback onPlanPressed;

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
                        subtitle: data.professionLocationLabel,
                        avatarUrl: data.avatarUrl,
                        onPressed: onSettingsPressed,
                        metrics: [
                          AppProfileMetric(
                            value: data.ratingLabel,
                            label: 'Avaliação',
                          ),
                          AppProfileMetric(
                            value: data.completedJobsLabel,
                            label: 'Concluídos',
                          ),
                          AppProfileMetric(
                            value: data.memberSinceLabel,
                            label: 'Na ProJardim',
                          ),
                        ],
                        actions: data.canSharePublicCard
                            ? Row(
                                children: [
                                  Expanded(
                                    child: _CardButton(
                                      icon: Icons.share_outlined,
                                      label: 'Partilhar',
                                      onPressed: onShareCardPressed,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Expanded(
                                    child: _CardButton(
                                      icon: Icons.qr_code_rounded,
                                      label: 'QR',
                                      onPressed: onQrPressed,
                                    ),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(
                      index: 1,
                      child: AppAccountMenuGroup(
                        items: [
                          const AppAccountMenuItem(
                            id: 'agenda',
                            label: 'Agenda',
                            icon: Icons.calendar_month_outlined,
                          ),
                          const AppAccountMenuItem(
                            id: 'help_requests',
                            label: 'Pedidos de ajuda',
                            icon: Icons.handshake_outlined,
                          ),
                          AppAccountMenuItem(
                            id: 'reviews',
                            label: 'As minhas avaliações',
                            icon: Icons.star_border_rounded,
                            trailingLabel: data.reviewsLabel,
                          ),
                          AppAccountMenuItem(
                            id: 'plan',
                            label: 'Plano',
                            icon: Icons.workspace_premium_outlined,
                            trailingLabel: data.planLabel,
                          ),
                          AppAccountMenuItem(
                            id: 'fleet_card',
                            label: 'Cartão frota',
                            icon: Icons.local_gas_station_outlined,
                            trailingLabel: data.fleetCardStatusLabel,
                          ),
                        ],
                        onItemPressed: (id) {
                          switch (id) {
                            case 'agenda':
                              onAgendaPressed();
                            case 'help_requests':
                              onHelpRequestsPressed();
                            case 'reviews':
                              onReviewsPressed();
                            case 'plan':
                              onPlanPressed();
                            case 'fleet_card':
                              onFleetCardPressed();
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
                            id: 'notifications',
                            label: 'Notificações',
                            icon: Icons.notifications_none_rounded,
                          ),
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
                            case 'notifications':
                              onNotificationsPressed();
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

/// "Partilhar" e "QR": contornados e iguais, como no design.
class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(0, AppSizes.headerIconButton),
        side: const BorderSide(color: AppColors.divider),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        textStyle: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      icon: Icon(icon, size: AppSizes.emphasisIcon),
      label: Text(label),
    );
  }
}
