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
    this.activeJobsTotal = 0,
    this.avatarImage,
    this.hasUnreadNotifications = false,
    this.loadingActiveJobs = false,
  });

  final String firstName;
  final String greetingSubtitle;

  final ImageProvider? avatarImage;
  final bool hasUnreadNotifications;

  /// Pedidos em curso (`open`/`confirmed`/`awaitingConfirmation`), já
  /// ordenados com o que precisa do cliente primeiro. Mostram-se numa só
  /// lista; pode vir cortada (ver [activeJobsTotal]).
  final List<ClientHomeActiveJobViewData> activeJobs;

  /// Total de pedidos em curso, mesmo os que não cabem em [activeJobs].
  final int activeJobsTotal;
  final bool loadingActiveJobs;
}

class ClientHomeActiveJobViewData {
  const ClientHomeActiveJobViewData({
    required this.id,
    required this.serviceLabel,
    required this.metadataLabel,
    required this.status,
    required this.icon,
    this.nextStepLabel,
    this.needsAction = false,
  });

  final String id;
  final String serviceLabel;
  final String metadataLabel;

  /// O que acontece a seguir, numa linha (ex.: "Tens 2 propostas para ver.").
  final String? nextStepLabel;

  /// Realça a linha quando o pedido espera por uma ação do cliente.
  final bool needsAction;

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
    this.onRefresh,
    super.key,
  });

  final ClientHomeViewData data;

  final VoidCallback onCreateJobPressed;
  final VoidCallback onNotificationsPressed;
  final VoidCallback onViewAllJobsPressed;

  final ValueChanged<String> onActiveJobPressed;

  /// Pull-to-refresh: o indicador roda até o `Future` terminar.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: _refreshable(CustomScrollView(
          // Rolável mesmo com pouco conteúdo, para o pull-to-refresh.
          physics: const AlwaysScrollableScrollPhysics(),
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
                        title: data.activeJobsTotal > 0
                            ? 'Pedidos em curso · ${data.activeJobsTotal}'
                            : 'Pedidos em curso',
                        actionLabel: 'Ver todos',
                        onActionPressed: onViewAllJobsPressed,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (data.loadingActiveJobs)
                      Column(
                        children: [
                          for (var i = 0; i < 2; i++) ...[
                            AppSkeletonShimmer(
                              child: Container(
                                height: 96,
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.card),
                                ),
                              ),
                            ),
                            if (i == 0) const SizedBox(height: AppSpacing.sm),
                          ],
                        ],
                      )
                    else if (data.activeJobs.isEmpty)
                      AppStaggeredEntrance(
                        index: 3,
                        child: _EmptyJobsCard(
                          onPressed: onCreateJobPressed,
                        ),
                      )
                    else
                      AppStaggeredEntrance(
                        index: 3,
                        child: _ActiveJobsList(
                          jobs: data.activeJobs,
                          hiddenCount:
                              data.activeJobsTotal - data.activeJobs.length,
                          onJobPressed: onActiveJobPressed,
                          onViewAllPressed: onViewAllJobsPressed,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        )),
      ),
    );
  }

  Widget _refreshable(Widget scrollable) {
    final refresh = onRefresh;
    if (refresh == null) return scrollable;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: refresh,
      child: scrollable,
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

/// Todos os pedidos em curso num só cartão, uma linha por pedido.
class _ActiveJobsList extends StatelessWidget {
  const _ActiveJobsList({
    required this.jobs,
    required this.hiddenCount,
    required this.onJobPressed,
    required this.onViewAllPressed,
  });

  final List<ClientHomeActiveJobViewData> jobs;
  final int hiddenCount;
  final ValueChanged<String> onJobPressed;
  final VoidCallback onViewAllPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: AppColors.surface,
        child: Column(
          children: [
            for (var i = 0; i < jobs.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.divider),
              _ActiveJobRow(
                job: jobs[i],
                onPressed: () => onJobPressed(jobs[i].id),
              ),
            ],
            if (hiddenCount > 0) ...[
              const Divider(height: 1, color: AppColors.divider),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onViewAllPressed,
                  child: Text(
                    hiddenCount == 1
                        ? 'Ver mais 1 pedido'
                        : 'Ver mais $hiddenCount pedidos',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActiveJobRow extends StatelessWidget {
  const _ActiveJobRow({required this.job, required this.onPressed});

  final ClientHomeActiveJobViewData job;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Icon(job.icon, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.serviceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  AppStatusBadge.fromPresentation(presentation: job.status),
                  if (job.nextStepLabel != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      job.nextStepLabel!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: job.needsAction
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontWeight:
                            job.needsAction ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ],
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
