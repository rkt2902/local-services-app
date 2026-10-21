import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/utils/day_greeting.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../../core/widgets/service_icon.dart';
import '../application/client_providers.dart';
import '../data/client_profile_model.dart';
import '../../jobs/application/client_job_next_step.dart';
import '../../jobs/application/client_jobs_refresh.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../../notifications/application/notification_providers.dart';
import 'widgets/client_home_view.dart' as view;

/// Ecrã inicial do cliente — wrapper de integração que liga
/// `clientProfileProvider`/`clientJobsProvider`/`serviceTypesProvider` ao
/// componente apresentacional em `widgets/client_home_view.dart`.
class ClientHomeScreen extends ConsumerWidget {
  const ClientHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(clientProfileProvider);

    return profileAsync.when(
      loading: () => const Scaffold(
        body: AppScreenLoadingSkeleton(),
      ),
      error: (e, _) => Scaffold(body: Center(child: Text(friendlyError(e)))),
      data: (profile) => _buildHome(context, ref, profile),
    );
  }

  Widget _buildHome(
    BuildContext context,
    WidgetRef ref,
    ClientProfile? profile,
  ) {
    final jobsAsync = ref.watch(clientJobsProvider);
    final serviceTypesAsync = ref.watch(serviceTypesProvider);
    final unreadCount = ref.watch(unreadCountProvider);

    final serviceTypes = serviceTypesAsync.asData?.value ?? const [];
    // Só o primeiro carregamento mostra o esqueleto: num pull-to-refresh a
    // lista atual fica à vista até chegar a nova.
    final loadingActiveJobs =
        (jobsAsync.isLoading && !jobsAsync.hasValue) ||
            (serviceTypesAsync.isLoading && !serviceTypesAsync.hasValue);

    var activeJobs = <view.ClientHomeActiveJobViewData>[];
    var activeTotal = 0;
    if (jobsAsync.hasValue) {
      final activeRaw = clientHomeActiveJobs(jobsAsync.value!);
      activeTotal = activeRaw.length;
      activeJobs = [
        for (final job in activeRaw.take(_homeMaxJobs))
          view.ClientHomeActiveJobViewData(
            id: job.id,
            serviceLabel: serviceTypes
                    .where((t) => t.id == job.serviceTypeId)
                    .map((t) => t.name)
                    .firstOrNull ??
                'Desconhecido',
            nextStepLabel: clientJobNextStepLabel(job, now: DateTime.now()),
            metadataLabel: _metadataLabel(job),
            status: job.status.presentation(
              proposalCount: job.proposalCount,
            ),
            icon: serviceTypeIconFor(serviceTypes, job.serviceTypeId),
            needsAction: clientJobNeedsAction(job),
          ),
      ];
    }

    final data = view.ClientHomeViewData(
      firstName: profile?.fullName.split(' ').first ?? '',
      greeting: dayGreeting(DateTime.now()),
      hasUnreadNotifications: unreadCount > 0,
      activeJobs: activeJobs,
      activeJobsTotal: activeTotal,
      loadingActiveJobs: loadingActiveJobs,
    );

    return view.ClientHomeScreen(
      data: data,
      onCreateJobPressed: () => context.push('/client/create-job'),
      onNotificationsPressed: () => context.push('/notifications'),
      onViewAllJobsPressed: () => context.go('/client/jobs'),
      onActiveJobPressed: (jobId) => context.push('/client/job/$jobId'),
      onRefresh: () => refreshClientJobs(ref),
    );
  }
}

const _homeMaxJobs = 5;

String _metadataLabel(JobRequest job) {
  final dateLabel = jobDeadlineLabel(
    job.dateMode,
    job.preferredDate,
    availabilityText: job.availabilityText,
  );
  final address =
      job.addressText.isEmpty ? 'Localização por definir' : job.addressText;
  return '$dateLabel · $address';
}
