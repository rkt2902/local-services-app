import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../../core/widgets/status_badges.dart' show jobStatusInfo;
import '../../client/application/client_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../../notifications/application/notification_providers.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';
import '../application/worker_providers.dart';
import '../data/worker_profile_model.dart';

/// Dados de apresentação do dashboard.
///
/// Construídos a partir dos providers reais dentro de [WorkerDashboardScreen].
/// O ecrã não contém dados de demonstração.
class WorkerDashboardViewData {
  const WorkerDashboardViewData({
    required this.workerFirstName,
    required this.dateLabel,
    required this.pendingCount,
    required this.scheduledCount,
    required this.opportunities,
    this.avatarImage,
    this.hasUnreadNotifications = false,
    this.nextJob,
  });

  final String workerFirstName;
  final String dateLabel;

  final int pendingCount;
  final int scheduledCount;

  final ImageProvider? avatarImage;
  final bool hasUnreadNotifications;

  final WorkerDashboardJobSummary? nextJob;

  final List<WorkerDashboardOpportunitySummary> opportunities;
}

/// Resumo do próximo trabalho agendado (primeiro item de
/// `scheduledWorkerProposalsProvider`, já ordenado por `confirmed_date`).
class WorkerDashboardJobSummary {
  const WorkerDashboardJobSummary({
    required this.id,
    required this.title,
    required this.dateTimeLabel,
    required this.clientName,
    required this.statusLabel,
    required this.statusColor,
    required this.icon,
  });

  /// Id do job (não da proposta) — usado por [onOpportunityPressed]-style
  /// callbacks que navegam por job. A navegação para o detalhe do próprio
  /// trabalho precisa também do id da proposta, resolvido no ecrã.
  final String id;
  final String title;
  final String dateTimeLabel;
  final String clientName;

  final String statusLabel;
  final AppStatusColor statusColor;

  final IconData icon;
}

/// Resumo de uma oportunidade próxima (job ainda sem proposta do worker).
class WorkerDashboardOpportunitySummary {
  const WorkerDashboardOpportunitySummary({
    required this.id,
    required this.title,
    required this.locationLabel,
    required this.priceLabel,
    required this.icon,
  });

  final String id;
  final String title;
  final String locationLabel;
  final String priceLabel;
  final IconData icon;
}

/// Ícone único para o MVP (categoria "Jardinagem" apenas).
const IconData _serviceIcon = Icons.yard_outlined;

/// Máximo de oportunidades mostradas no carrossel horizontal.
const int _maxOpportunities = 6;

class WorkerDashboardScreen extends ConsumerWidget {
  const WorkerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workerAsync = ref.watch(workerProfileProvider);

    return workerAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text(friendlyError(e)))),
      data: (workerProfile) =>
          _buildDashboard(context, ref, workerProfile),
    );
  }

  Widget _buildDashboard(
      BuildContext context, WidgetRef ref, WorkerProfile? workerProfile) {
    final serviceTypes = ref.watch(serviceTypesProvider).asData?.value ?? [];
    final pendingCount =
        ref.watch(pendingWorkerProposalsProvider).asData?.value.length ?? 0;
    final scheduledRaw =
        ref.watch(scheduledWorkerProposalsProvider).asData?.value ??
            const <Map<String, dynamic>>[];
    final opportunitiesRaw =
        ref.watch(jobsInRadiusProvider).asData?.value ?? const <JobRequest>[];
    final unreadCount = ref.watch(unreadCountProvider);

    // Primeiro item de scheduledWorkerProposalsProvider — a lista já vem
    // ordenada por confirmed_date ascendente (ver proposal_repository.dart),
    // por isso é literalmente "o próximo trabalho agendado".
    (JobProposal, JobRequest)? nextEntry;
    if (scheduledRaw.isNotEmpty) {
      final jobJson = scheduledRaw.first['job_requests'];
      if (jobJson != null) {
        nextEntry = (
          JobProposal.fromJson(Map<String, dynamic>.from(scheduledRaw.first)),
          JobRequest.fromJson(Map<String, dynamic>.from(jobJson as Map)),
        );
      }
    }

    final clientInfoAsync = nextEntry != null
        ? ref.watch(clientBasicInfoProvider(nextEntry.$2.clientId))
        : null;

    WorkerDashboardJobSummary? nextJob;
    String? nextJobProposalId;
    if (nextEntry != null) {
      final (proposal, job) = nextEntry;
      nextJobProposalId = proposal.id;
      final serviceType =
          serviceTypes.where((s) => s.id == job.serviceTypeId).firstOrNull;
      // scheduledWorkerProposalsProvider só devolve confirmed/awaiting_confirmation
      // — nenhum dos dois é neutro, por isso o fallback nunca é exercido.
      final (statusLabel, statusColor) = jobStatusInfo(job.status, 0);
      nextJob = WorkerDashboardJobSummary(
        id: job.id,
        title: serviceType?.name ?? '—',
        dateTimeLabel: _confirmedScheduleLabel(job),
        clientName: clientInfoAsync?.asData?.value['full_name'] ?? '',
        statusLabel: statusLabel,
        statusColor: statusColor ?? AppStatusColor.waiting,
        icon: _serviceIcon,
      );
    }

    final opportunities = <WorkerDashboardOpportunitySummary>[
      for (final job in opportunitiesRaw.take(_maxOpportunities))
        WorkerDashboardOpportunitySummary(
          id: job.id,
          title: (serviceTypes.where((s) => s.id == job.serviceTypeId).firstOrNull)
                  ?.name ??
              '—',
          locationLabel: _distanceLabel(workerProfile, job),
          // O MVP não tem preço no pedido — o valor só existe depois de uma
          // proposta. Ver docs/project_overview.md ("Valor exibido é SEMPRE
          // estimado").
          priceLabel: 'Preço a combinar',
          icon: _serviceIcon,
        ),
    ];

    final fullName = workerProfile?.fullName.trim() ?? '';

    final data = WorkerDashboardViewData(
      workerFirstName: fullName.isEmpty ? '' : fullName.split(' ').first,
      dateLabel: DateFormat('dd/MM/yyyy').format(DateTime.now()),
      pendingCount: pendingCount,
      scheduledCount: scheduledRaw.length,
      opportunities: opportunities,
      avatarImage: workerProfile?.avatarUrl != null
          ? NetworkImage(workerProfile!.avatarUrl!)
          : null,
      hasUnreadNotifications: unreadCount > 0,
      nextJob: nextJob,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    _DashboardHeader(
                      workerFirstName: data.workerFirstName,
                      dateLabel: data.dateLabel,
                      avatarImage: data.avatarImage,
                      hasUnreadNotifications: data.hasUnreadNotifications,
                      onNotificationsPressed: () =>
                          context.push('/notifications'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _DashboardMetrics(
                      pendingCount: data.pendingCount,
                      scheduledCount: data.scheduledCount,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _SectionHeader(
                      title: 'Próximo trabalho',
                      actionLabel: 'Ver todos',
                      onActionPressed: () => context.go('/worker/jobs'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _NextJobSection(
                      job: data.nextJob,
                      onPressed: nextJobProposalId == null
                          ? null
                          : (jobId) => context.push(
                              '/worker/my-job/$nextJobProposalId?jobId=$jobId'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const _SectionHeader(
                      title: 'Oportunidades perto de si',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _NearbyOpportunitiesSection(
                      opportunities: data.opportunities,
                      onOpportunityPressed: (id) =>
                          context.go('/worker/job/$id'),
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

String _confirmedScheduleLabel(JobRequest job) {
  if (job.confirmedDate == null) return 'Data a combinar';
  final date = DateFormat('dd/MM/yyyy').format(job.confirmedDate!);
  if (job.confirmedFlexible) return '$date (horário flexível)';
  if (job.confirmedTime != null) return '$date às ${job.confirmedTime}';
  return date;
}

String _distanceLabel(WorkerProfile? workerProfile, JobRequest job) {
  if (workerProfile == null) return '';
  final distanceMeters = Geolocator.distanceBetween(
    workerProfile.baseLat,
    workerProfile.baseLng,
    job.locationLat,
    job.locationLng,
  );
  return distanceMeters < 1000
      ? '${distanceMeters.round()} m'
      : '${(distanceMeters / 1000).toStringAsFixed(1)} km';
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.workerFirstName,
    required this.dateLabel,
    required this.avatarImage,
    required this.hasUnreadNotifications,
    required this.onNotificationsPressed,
  });

  final String workerFirstName;
  final String dateLabel;
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
                'Olá, $workerFirstName 👋',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                dateLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _NotificationButton(
          hasUnreadNotifications: hasUnreadNotifications,
          onPressed: onNotificationsPressed,
        ),
      ],
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({
    required this.hasUnreadNotifications,
    required this.onPressed,
  });

  final bool hasUnreadNotifications;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: hasUnreadNotifications ? 'Notificações não lidas' : 'Notificações',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            onPressed: onPressed,
            tooltip: 'Notificações',
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: AppColors.textSecondary,
            ),
          ),
          if (hasUnreadNotifications)
            Positioned(
              top: AppSpacing.xs,
              right: AppSpacing.xs,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppStatusColor.cancelled.foreground,
                  border: Border.all(color: AppColors.background),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Só 2 cartões (Pendentes / Agendados) — sem dados agregados de propostas
/// enviadas nem de receita mensal (nenhum dos dois existe hoje no backend;
/// ver docs/improvements.md, "Dashboard do jardineiro").
class _DashboardMetrics extends StatelessWidget {
  const _DashboardMetrics({
    required this.pendingCount,
    required this.scheduledCount,
  });

  final int pendingCount;
  final int scheduledCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            value: pendingCount.toString(),
            label: 'Pendentes',
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _MetricCard(
            value: scheduledCount.toString(),
            label: 'Agendados',
            highlighted: true,
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.value,
    required this.label,
    this.highlighted = false,
  });

  final String value;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final backgroundColor = highlighted ? AppColors.primary : AppColors.surface;
    final valueColor = highlighted ? AppColors.surface : AppColors.primary;
    final labelColor = highlighted ? AppColors.surface : AppColors.textSecondary;

    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: highlighted ? null : Border.all(color: AppColors.divider),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: textTheme.displaySmall?.copyWith(color: valueColor),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: textTheme.labelMedium?.copyWith(color: labelColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onActionPressed,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onActionPressed,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xs,
              ),
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: textTheme.labelMedium,
            ),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

class _NextJobSection extends StatelessWidget {
  const _NextJobSection({
    required this.job,
    required this.onPressed,
  });

  final WorkerDashboardJobSummary? job;
  final ValueChanged<String>? onPressed;

  @override
  Widget build(BuildContext context) {
    if (job == null) {
      return const _DashboardEmptyCard(
        icon: Icons.event_available_outlined,
        message: 'Ainda não existem trabalhos agendados.',
      );
    }

    return Material(
      color: AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onPressed == null ? null : () => onPressed!(job!.id),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              _ServiceIcon(icon: job!.icon),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _NextJobContent(job: job!)),
              const SizedBox(width: AppSpacing.sm),
              AppStatusBadge(
                label: job!.statusLabel,
                statusColor: job!.statusColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextJobContent extends StatelessWidget {
  const _NextJobContent({required this.job});

  final WorkerDashboardJobSummary job;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          job.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '${job.dateTimeLabel} · ${job.clientName}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _NearbyOpportunitiesSection extends StatelessWidget {
  const _NearbyOpportunitiesSection({
    required this.opportunities,
    required this.onOpportunityPressed,
  });

  final List<WorkerDashboardOpportunitySummary> opportunities;
  final ValueChanged<String> onOpportunityPressed;

  @override
  Widget build(BuildContext context) {
    if (opportunities.isEmpty) {
      return const _DashboardEmptyCard(
        icon: Icons.search_off_rounded,
        message: 'Não existem oportunidades disponíveis perto de si.',
      );
    }

    return SizedBox(
      height: 142,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: opportunities.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final opportunity = opportunities[index];
          return _OpportunityCard(
            opportunity: opportunity,
            onPressed: () => onOpportunityPressed(opportunity.id),
          );
        },
      ),
    );
  }
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({
    required this.opportunity,
    required this.onPressed,
  });

  final WorkerDashboardOpportunitySummary opportunity;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          width: 150,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ServiceIcon(icon: opportunity.icon, compact: true),
              const Spacer(),
              Text(
                opportunity.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium?.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                opportunity.locationLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                opportunity.priceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(color: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceIcon extends StatelessWidget {
  const _ServiceIcon({required this.icon, this.compact = false});

  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 32.0 : 42.0;
    final iconSize = compact ? 18.0 : 22.0;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Icon(icon, size: iconSize, color: AppColors.primary),
    );
  }
}

class _DashboardEmptyCard extends StatelessWidget {
  const _DashboardEmptyCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
