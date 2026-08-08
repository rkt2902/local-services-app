import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/error_utils.dart';
import '../application/client_providers.dart';
import '../data/client_profile_model.dart';
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
        body: Center(child: CircularProgressIndicator()),
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
    final loadingActiveJobs =
        jobsAsync.isLoading || serviceTypesAsync.isLoading;

    var activeJobs = <view.ClientHomeActiveJobViewData>[];
    if (jobsAsync.hasValue) {
      final activeRaw = jobsAsync.value!
          .where((j) =>
              j.status == JobStatus.open || j.status == JobStatus.confirmed)
          .take(3);
      activeJobs = [
        for (final job in activeRaw)
          view.ClientHomeActiveJobViewData(
            id: job.id,
            referenceLabel: '#${job.id.substring(0, 8)}',
            serviceLabel: serviceTypes
                    .where((t) => t.id == job.serviceTypeId)
                    .map((t) => t.name)
                    .firstOrNull ??
                'Desconhecido',
            metadataLabel: _metadataLabel(job),
            status: job.status.presentation(
              proposalCount: job.proposalCount,
            ),
            icon: Icons.yard_outlined,
          ),
      ];
    }

    final data = view.ClientHomeViewData(
      firstName: profile?.fullName.split(' ').first ?? '',
      greetingSubtitle: DateFormat('dd/MM/yyyy').format(DateTime.now()),
      avatarImage:
          profile?.avatarUrl != null ? NetworkImage(profile!.avatarUrl!) : null,
      hasUnreadNotifications: unreadCount > 0,
      activeJobs: activeJobs,
      loadingActiveJobs: loadingActiveJobs,
    );

    return view.ClientHomeScreen(
      data: data,
      onCreateJobPressed: () => context.push('/client/create-job'),
      onNotificationsPressed: () => context.push('/notifications'),
      onViewAllJobsPressed: () => context.push('/client/jobs'),
      onActiveJobPressed: (jobId) => context.push('/client/job/$jobId'),
    );
  }
}

String _metadataLabel(JobRequest job) {
  final dateLabel = job.preferredDate == null
      ? 'Flexível'
      : DateFormat('dd/MM/yyyy').format(job.preferredDate!);
  final address =
      job.addressText.isEmpty ? 'Localização por definir' : job.addressText;
  return '$dateLabel · $address';
}
