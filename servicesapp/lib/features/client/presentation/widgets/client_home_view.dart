import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';
import 'package:servicesapp/core/theme/app_status_presentation.dart';
import 'package:servicesapp/core/widgets/app_motion.dart';
import 'package:servicesapp/core/widgets/app_status_badge.dart';

/// Dados de apresentação da Home do cliente.
///
/// A integração (client_home_screen.dart) mapeia os models reais
/// (ClientProfile/JobRequest) para esta estrutura.
class ClientHomeViewData {
  const ClientHomeViewData({
    required this.firstName,
    required this.greetingSubtitle,
    required this.activeJobs,
    this.avatarImage,
    this.hasUnreadNotifications = false,
    this.loadingActiveJobs = false,
  });

  final String firstName;
  final String greetingSubtitle;

  final ImageProvider? avatarImage;
  final bool hasUnreadNotifications;

  /// Jobs com estado `open`/`confirmed` — o cliente pode ter mais do que um
  /// em simultâneo, por isso é uma lista (máx. 3), não um único destaque.
  final List<ClientHomeActiveJobViewData> activeJobs;
  final bool loadingActiveJobs;
}

class ClientHomeActiveJobViewData {
  const ClientHomeActiveJobViewData({
    required this.id,
    required this.referenceLabel,
    required this.serviceLabel,
    required this.metadataLabel,
    required this.status,
    required this.icon,
  });

  final String id;
  final String referenceLabel;
  final String serviceLabel;
  final String metadataLabel;

  final AppStatusPresentation status;
  final IconData icon;
}

/// Ecrã inicial do cliente. Sem `bottomNavigationBar` — fica só no
/// `ClientShell`, que já envolve esta rota.
class ClientHomeScreen extends StatelessWidget {
  const ClientHomeScreen({
    required this.data,
    required this.onCreateJobPressed,
    required this.onNotificationsPressed,
    required this.onActiveJobPressed,
    required this.onViewAllJobsPressed,
    super.key,
  });

  final ClientHomeViewData data;

  final VoidCallback onCreateJobPressed;
  final VoidCallback onNotificationsPressed;
  final VoidCallback onViewAllJobsPressed;

  final ValueChanged<String> onActiveJobPressed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    AppStaggeredEntrance(
                      index: 0,
                      child: _ClientHeader(
                        firstName: data.firstName,
                        subtitle: data.greetingSubtitle,
                        avatarImage: data.avatarImage,
                        hasUnreadNotifications:
                            data.hasUnreadNotifications,
                        onNotificationsPressed:
                            onNotificationsPressed,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 1,
                      child: _CreateJobButton(
                        onPressed: onCreateJobPressed,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 2,
                      child: _SectionHeader(
                        title: 'Pedidos ativos',
                        actionLabel: 'Ver todos',
                        onActionPressed: onViewAllJobsPressed,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (data.loadingActiveJobs)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: AppSpacing.lg,
                        ),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    else if (data.activeJobs.isEmpty)
                      AppStaggeredEntrance(
                        index: 3,
                        child: _EmptyJobsCard(
                          onPressed: onCreateJobPressed,
                        ),
                      )
                    else
                      for (
                        var index = 0;
                        index < data.activeJobs.length;
                        index++
                      )
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: index == data.activeJobs.length - 1
                                ? 0
                                : AppSpacing.sm,
                          ),
                          child: AppStaggeredEntrance(
                            index: 3 + index,
                            child: _ActiveJobCard(
                              job: data.activeJobs[index],
                              onPressed: () => onActiveJobPressed(
                                data.activeJobs[index].id,
                              ),
                            ),
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

class _ClientHeader extends StatelessWidget {
  const _ClientHeader({
    required this.firstName,
    required this.subtitle,
    required this.avatarImage,
    required this.hasUnreadNotifications,
    required this.onNotificationsPressed,
  });

  final String firstName;
  final String subtitle;
  final ImageProvider? avatarImage;
  final bool hasUnreadNotifications;
  final VoidCallback onNotificationsPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.primaryContainer,
          backgroundImage: avatarImage,
          child: avatarImage == null
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
                firstName.isEmpty ? 'Olá 👋' : 'Olá, $firstName 👋',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        _NotificationsButton(
          hasUnread: hasUnreadNotifications,
          onPressed: onNotificationsPressed,
        ),
      ],
    );
  }
}

class _NotificationsButton extends StatelessWidget {
  const _NotificationsButton({
    required this.hasUnread,
    required this.onPressed,
  });

  final bool hasUnread;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          onPressed: onPressed,
          tooltip: 'Alertas',
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: AppColors.textSecondary,
          ),
        ),
        if (hasUnread)
          Positioned(
            top: AppSpacing.xs,
            right: AppSpacing.xs,
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
              ),
            ),
          ),
      ],
    );
  }
}

class _CreateJobButton extends StatelessWidget {
  const _CreateJobButton({
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStateProperty.resolveWith<Color>(
            (states) {
              if (states.contains(WidgetState.pressed)) {
                return AppColors.primaryPressed;
              }

              return AppColors.primary;
            },
          ),
          foregroundColor: const WidgetStatePropertyAll(
            AppColors.surface,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                AppRadius.input,
              ),
            ),
          ),
          textStyle: WidgetStatePropertyAll(
            textTheme.titleMedium,
          ),
        ),
        icon: const Icon(
          Icons.add_rounded,
        ),
        label: const Text('Criar pedido'),
      ),
    );
  }
}

class _ActiveJobCard extends StatelessWidget {
  const _ActiveJobCard({
    required this.job,
    required this.onPressed,
  });

  final ClientHomeActiveJobViewData job;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(
        AppRadius.card,
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(
          AppRadius.card,
        ),
        child: Container(
          padding: const EdgeInsets.all(
            AppSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              AppRadius.card,
            ),
            border: Border.all(
              color: AppColors.divider,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'PEDIDO ATIVO',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  AppStatusBadge.fromPresentation(
                    presentation: job.status,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(
                        AppRadius.input,
                      ),
                    ),
                    child: Icon(
                      job.icon,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${job.referenceLabel} · ${job.serviceLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          job.metadataLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onActionPressed,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onActionPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ),
        TextButton(
          onPressed: onActionPressed,
          child: Text(actionLabel),
        ),
      ],
    );
  }
}

class _EmptyJobsCard extends StatelessWidget {
  const _EmptyJobsCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(
          AppRadius.card,
        ),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.yard_outlined,
            size: 40,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Ainda não tens pedidos ativos.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: onPressed,
            child: const Text('Criar primeiro pedido'),
          ),
        ],
      ),
    );
  }
}
