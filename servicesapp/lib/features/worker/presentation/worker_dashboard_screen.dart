import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/price_labels.dart';
import '../../../core/constants/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../../core/widgets/service_icon.dart';
import '../../../core/widgets/todo_row.dart';
import '../../auth/application/auth_providers.dart';
import '../../client/application/client_providers.dart';
import '../../help_requests/application/help_request_providers.dart';
import '../../help_requests/data/help_request_model.dart';
import '../../ratings/application/rating_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../../notifications/application/notification_providers.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';
import '../application/worker_providers.dart';
import '../application/worker_todo.dart';
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

/// Máximo de oportunidades mostradas no carrossel horizontal.
const int _maxOpportunities = 6;

class WorkerDashboardScreen extends ConsumerWidget {
  const WorkerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workerAsync = ref.watch(workerProfileProvider);

    return workerAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(bottom: false, child: _DashboardSkeleton()),
      ),
      error: (e, _) => Scaffold(body: Center(child: Text(friendlyError(e)))),
      data: (workerProfile) => _buildDashboard(context, ref, workerProfile),
    );
  }

  Widget _buildDashboard(
    BuildContext context,
    WidgetRef ref,
    WorkerProfile? workerProfile,
  ) {
    final serviceTypes = ref.watch(serviceTypesProvider).asData?.value ?? [];
    final pendingCount =
        ref.watch(pendingWorkerProposalsProvider).asData?.value.length ?? 0;
    final scheduledRaw =
        ref.watch(scheduledWorkerProposalsProvider).asData?.value ??
        const <Map<String, dynamic>>[];
    final opportunitiesRaw =
        ref.watch(jobsInRadiusProvider).asData?.value ?? const <JobRequest>[];
    final unreadCount = ref.watch(unreadCountProvider);
    final todoItems = _buildTodo(ref, scheduledRaw);

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
      final serviceType = serviceTypes
          .where((s) => s.id == job.serviceTypeId)
          .firstOrNull;
      final current = job.status.presentation();
      nextJob = WorkerDashboardJobSummary(
        id: job.id,
        title: serviceType?.name ?? '—',
        dateTimeLabel: _confirmedScheduleLabel(job),
        clientName: clientInfoAsync?.asData?.value['full_name'] ?? '',
        statusLabel: current.label,
        statusColor: current.color,
        icon: serviceIconFor(serviceType?.icon),
      );
    }

    final opportunities = <WorkerDashboardOpportunitySummary>[
      for (final job in opportunitiesRaw.take(_maxOpportunities))
        WorkerDashboardOpportunitySummary(
          id: job.id,
          title:
              (serviceTypes.where((s) => s.id == job.serviceTypeId).firstOrNull)
                  ?.name ??
              '—',
          locationLabel: _distanceLabel(workerProfile, job),
          // O MVP não tem preço no pedido — o valor só existe depois de uma
          // proposta. Ver docs/project_overview.md ("Valor exibido é SEMPRE
          // estimado").
          priceLabel: 'Preço a combinar',
          icon: serviceTypeIconFor(serviceTypes, job.serviceTypeId),
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
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => _refresh(ref),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.xl,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    AppStaggeredEntrance(
                      index: 0,
                      child: _DashboardHeader(
                        workerFirstName: data.workerFirstName,
                        dateLabel: data.dateLabel,
                        avatarImage: data.avatarImage,
                        hasUnreadNotifications: data.hasUnreadNotifications,
                        onNotificationsPressed: () =>
                            context.push('/notifications'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 1,
                      child: _DashboardMetrics(
                        pendingCount: data.pendingCount,
                        scheduledCount: data.scheduledCount,
                      ),
                    ),
                    if (todoItems.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      AppStaggeredEntrance(
                        index: 2,
                        child: _TodoCard(
                          items: todoItems,
                          onPressed: (target) =>
                              _openTodoTarget(context, target),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionHeader(
                            title: 'Próximo trabalho',
                            actionLabel: 'Ver todos',
                            onActionPressed: () => context.go(
                              '/worker/jobs',
                              extra: {
                                'initialTab': 'scheduled',
                                'highlightedJobId': ?nextJobProposalId,
                              },
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _NextJobSection(
                            job: data.nextJob,
                            onPressed: nextJobProposalId == null
                                ? null
                                : (jobId) => context.push(
                                    '/worker/my-job/$nextJobProposalId?jobId=$jobId',
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 4,
                      child: const _SectionHeader(
                        title: 'Oportunidades perto de ti',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _NearbyOpportunitiesSection(
                      opportunities: data.opportunities,
                      onOpportunityPressed: (id) =>
                          context.push('/worker/job/$id'),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pull-to-refresh: tudo o que o dashboard mostra.
  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(workerProfileProvider);
    ref.invalidate(pendingWorkerProposalsProvider);
    ref.invalidate(scheduledWorkerProposalsProvider);
    ref.invalidate(completedWorkerProposalsProvider(0));
    ref.invalidate(jobsInRadiusProvider);
    ref.invalidate(myHelpAcceptancesProvider);
    ref.invalidate(myRatingsGivenProvider);
    ref.invalidate(helpRequestsForJobProvider);
    ref.invalidate(candidatesForHelpRequestProvider);
    try {
      await ref.read(scheduledWorkerProposalsProvider.future);
    } catch (_) {
      // O erro aparece nas próprias secções; o indicador só tem de fechar.
    }
  }

  /// "O que falta fazer": só dados de providers que o dashboard já usa,
  /// mais os candidatos dos primeiros [todoCandidatesJobCap] trabalhos.
  List<WorkerTodoItem> _buildTodo(
    WidgetRef ref,
    List<Map<String, dynamic>> scheduledRaw,
  ) {
    final myUserId = ref.watch(currentUserIdProvider) ?? '';
    final scheduledJobs = <WorkerTodoScheduledJob>[];
    for (final row in scheduledRaw) {
      final jobJson = row['job_requests'];
      if (jobJson is! Map) continue;
      final job = JobRequest.fromJson(Map<String, dynamic>.from(jobJson));
      scheduledJobs.add(
        WorkerTodoScheduledJob(
          proposalId: row['id'] as String,
          jobId: job.id,
          status: job.status,
          confirmedDate: job.confirmedDate,
          rescheduleStatus: job.rescheduleStatus,
          rescheduleProposedBy: job.rescheduleProposedBy,
        ),
      );
    }

    final helpAcceptances =
        ref.watch(myHelpAcceptancesProvider).asData?.value ??
        const <HelpAcceptanceSummary>[];

    final completedRaw = ref
        .watch(completedWorkerProposalsProvider(0))
        .asData
        ?.value;
    final completedJobs = completedRaw == null
        ? null
        : [
            for (final row in completedRaw)
              if (row['job_requests'] case final Map jobJson)
                _completedJob(row['id'] as String, jobJson),
          ];
    final given = ref.watch(myRatingsGivenProvider).asData?.value;
    final ratingsGiven = given == null
        ? null
        : {for (final r in given) (r.jobId, r.partyId)};

    final pendingCandidatesByJob = <String, int>{};
    final confirmedJobIds = scheduledJobs
        .where((j) => j.status == JobStatus.confirmed)
        .map((j) => j.jobId)
        .take(todoCandidatesJobCap);
    for (final jobId in confirmedJobIds) {
      final helpRequests =
          ref.watch(helpRequestsForJobProvider(jobId)).asData?.value ??
          const <HelpRequest>[];
      var count = 0;
      for (final hr in helpRequests) {
        if (hr.status != HelpRequestStatus.open) continue;
        final candidates =
            ref.watch(candidatesForHelpRequestProvider(hr.id)).asData?.value ??
            const <HelpAcceptance>[];
        count += candidates
            .where((c) => c.status == HelpAcceptanceStatus.pending)
            .length;
      }
      if (count > 0) pendingCandidatesByJob[jobId] = count;
    }

    return buildWorkerTodo(
      myUserId: myUserId,
      today: DateTime.now(),
      scheduledJobs: scheduledJobs,
      helpAcceptances: helpAcceptances,
      completedJobs: completedJobs,
      ratingsGiven: ratingsGiven,
      pendingCandidatesByJob: pendingCandidatesByJob,
    );
  }

  static WorkerTodoCompletedJob _completedJob(String proposalId, Map jobJson) {
    final job = JobRequest.fromJson(Map<String, dynamic>.from(jobJson));
    return WorkerTodoCompletedJob(
      proposalId: proposalId,
      jobId: job.id,
      clientId: job.clientId,
      confirmedDate: job.confirmedDate,
    );
  }

  void _openTodoTarget(BuildContext context, WorkerTodoTarget target) {
    if (target.push) {
      context.push(target.location, extra: target.extra);
    } else {
      context.go(target.location, extra: target.extra);
    }
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
      : '${decimalLabel(distanceMeters / 1000, 1)} km';
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
    final labelColor = highlighted
        ? AppColors.surface
        : AppColors.textSecondary;

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
            style: textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
            ),
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

/// Cartão "O que falta fazer": uma linha por tipo de pendência, cada uma
/// leva ao sítio certo. Só aparece quando há alguma coisa.
class _TodoCard extends StatelessWidget {
  const _TodoCard({required this.items, required this.onPressed});

  final List<WorkerTodoItem> items;
  final ValueChanged<WorkerTodoTarget> onPressed;

  Widget _todoRow(WorkerTodoItem item) {
    final (icon, tone) = _todoStyle(item.kind);
    return TodoRow(
      icon: icon,
      tone: tone,
      title: item.label,
      onPressed: () => onPressed(item.target),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.xxs,
              ),
              child: Text(
                'O que falta fazer',
                style: textTheme.titleMedium?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.divider),
              _todoRow(items[i]),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ícone e cor de cada tipo de pendência (design U1, `TodoRow`).
(IconData, AppStatusColor) _todoStyle(WorkerTodoKind kind) => switch (kind) {
      WorkerTodoKind.rescheduleToAnswer => (
        Icons.edit_calendar_outlined,
        AppStatusColor.waiting,
      ),
      WorkerTodoKind.workToday => (
        Icons.today_outlined,
        AppStatusColor.success,
      ),
      WorkerTodoKind.toMarkDone => (
        Icons.task_alt_rounded,
        AppStatusColor.cancelled,
      ),
      WorkerTodoKind.ratingsToGive => (
        Icons.star_outline_rounded,
        AppStatusColor.info,
      ),
      WorkerTodoKind.candidatesToDecide => (
        Icons.person_search_outlined,
        AppStatusColor.waiting,
      ),
      WorkerTodoKind.pendingApplications => (
        Icons.hourglass_top_rounded,
        AppStatusColor.neutral,
      ),
    };

class _NextJobSection extends StatelessWidget {
  const _NextJobSection({required this.job, required this.onPressed});

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
          style: textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
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
        message: 'Não existem oportunidades disponíveis perto de ti.',
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
          return AppStaggeredEntrance(
            index: index,
            child: _OpportunityCard(
              opportunity: opportunity,
              onPressed: () => onOpportunityPressed(opportunity.id),
            ),
          );
        },
      ),
    );
  }
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({required this.opportunity, required this.onPressed});

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
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                opportunity.locationLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                opportunity.priceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  color: AppColors.primary,
                ),
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
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppSkeletonShimmer(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.divider,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _SkeletonBlock(width: 140, height: 16),
                      SizedBox(height: AppSpacing.xxs),
                      _SkeletonBlock(width: 90, height: 12),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Row(
              children: [
                Expanded(
                  child: _SkeletonBlock(width: double.infinity, height: 96),
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _SkeletonBlock(width: double.infinity, height: 96),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const _SkeletonBlock(width: 140, height: 18),
            const SizedBox(height: AppSpacing.sm),
            const _SkeletonBlock(width: double.infinity, height: 74),
            const SizedBox(height: AppSpacing.md),
            const _SkeletonBlock(width: 180, height: 18),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: const [
                Expanded(
                  child: _SkeletonBlock(width: double.infinity, height: 142),
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _SkeletonBlock(width: double.infinity, height: 142),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.divider,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
    );
  }
}
