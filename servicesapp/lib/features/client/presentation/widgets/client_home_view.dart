import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncValue;

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_sizes.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';
import 'package:servicesapp/core/theme/app_status_presentation.dart';
import 'package:servicesapp/core/widgets/app_empty_state.dart';
import 'package:servicesapp/core/widgets/app_motion.dart';
import 'package:servicesapp/core/widgets/home_notification_button.dart';
import 'package:servicesapp/core/widgets/next_step_row.dart';

import 'your_gardeners_section.dart';

/// Dados de apresentação da Home do cliente.
///
/// A integração (client_home_screen.dart) mapeia os models reais
/// (ClientProfile/JobRequest) para esta estrutura.
class ClientHomeViewData {
  const ClientHomeViewData({
    required this.firstName,
    required this.greeting,
    required this.activeJobs,
    this.activeJobsTotal = 0,
    this.hasUnreadNotifications = false,
    this.loadingActiveJobs = false,
  });

  final String firstName;

  /// "Bom dia" / "Boa tarde" / "Boa noite" (`dayGreeting`).
  final String greeting;
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
    this.gardeners = const AsyncValue.data([]),
    this.onRepeatHireGardener,
    this.onRetryGardeners,
    this.onRefresh,
    super.key,
  });

  final ClientHomeViewData data;

  /// "Os teus jardineiros" (design A5). Lista vazia: a secção não aparece.
  final AsyncValue<List<YourGardenerCardViewData>> gardeners;
  final ValueChanged<YourGardenerCardViewData>? onRepeatHireGardener;
  final VoidCallback? onRetryGardeners;

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
                AppSpacing.s18,
                AppSpacing.md,
                AppSpacing.s18,
                AppSpacing.xl,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    AppStaggeredEntrance(
                      index: 0,
                      child: _ClientHeader(
                        firstName: data.firstName,
                        greeting: data.greeting,
                        hasUnreadNotifications: data.hasUnreadNotifications,
                        onNotificationsPressed: onNotificationsPressed,
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
                      child: YourGardenersSection(
                        dataAsync: gardeners,
                        onRepeatHire: onRepeatHireGardener ?? (_) {},
                        onRetry: onRetryGardeners,
                      ),
                    ),
                    AppStaggeredEntrance(
                      index: 3,
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
                        index: 4,
                        child: _EmptyJobsCard(
                          onPressed: onCreateJobPressed,
                        ),
                      )
                    else
                      AppStaggeredEntrance(
                        index: 4,
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
    required this.greeting,
    required this.hasUnreadNotifications,
    required this.onNotificationsPressed,
  });

  final String firstName;
  final String greeting;
  final bool hasUnreadNotifications;
  final VoidCallback onNotificationsPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                firstName.isEmpty ? 'Olá' : 'Olá, $firstName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.headlineSmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        HomeNotificationButton(
          hasUnread: hasUnreadNotifications,
          onPressed: onNotificationsPressed,
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
      height: AppSizes.buttonHeight,
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
              NextStepRow(
                icon: jobs[i].icon,
                title: jobs[i].serviceLabel,
                status: jobs[i].status,
                subtitle: jobs[i].needsAction
                    ? (jobs[i].nextStepLabel ?? jobs[i].metadataLabel)
                    : jobs[i].metadataLabel,
                needsAction: jobs[i].needsAction,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: AppEmptyState(
        icon: Icons.yard_outlined,
        title: 'Ainda sem pedidos ativos',
        message:
            'Cria um pedido e recebe propostas de jardineiros perto de ti.',
        actionLabel: 'Criar primeiro pedido',
        onAction: onPressed,
      ),
    );
  }
}
