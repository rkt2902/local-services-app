import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/utils/day_greeting.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/service_icon.dart';
import '../application/client_create_job_wizard_provider.dart';
import '../application/client_providers.dart';
import '../data/client_profile_model.dart';
import '../../jobs/application/client_job_next_step.dart';
import '../../jobs/application/client_jobs_refresh.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../../jobs/application/direct_request_labels.dart';
import '../../jobs/data/direct_request_models.dart';
import 'repeat_hire_launcher.dart';
import 'widgets/client_home_view.dart' as view;
import 'widgets/your_gardeners_section.dart';

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
      activeJobs: activeJobs,
      activeJobsTotal: activeTotal,
      loadingActiveJobs: loadingActiveJobs,
    );

    final now = DateTime.now();
    final gardenersAsync = ref.watch(myPreviousWorkersProvider);
    final gardeners = gardenersAsync.whenData((workers) => [
          for (final w in workers)
            YourGardenerCardViewData(
              workerId: w.workerId,
              workerName: firstNameOr(w.workerName, 'Jardineiro'),
              workerInitial:
                  initialOf(w.workerName.isEmpty ? 'Jardineiro' : w.workerName),
              workerAvatarUrl: w.workerAvatarUrl,
              lastServiceLabel: serviceTypes
                      .where((t) => t.id == w.serviceTypeId)
                      .map((t) => t.name)
                      .firstOrNull ??
                  '',
              lastWorkedLabel:
                  w.jobDate == null ? '' : timeAgoLabel(w.jobDate!, now),
            ),
        ]);
    final workersById = {
      for (final w in gardenersAsync.asData?.value ?? const <PreviousWorker>[])
        w.workerId: w,
    };

    return view.ClientHomeScreen(
      data: data,
      gardeners: gardeners,
      onRetryGardeners: () => ref.invalidate(myPreviousWorkersProvider),
      onRepeatHireGardener: (card) {
        final worker = workersById[card.workerId];
        if (worker != null) _repeatHire(context, ref, worker);
      },
      onCreateJobPressed: () {
        ref.read(clientCreateJobWizardProvider.notifier).clearDirectWorker();
        context.push('/client/create-job');
      },
      onViewAllJobsPressed: () => context.go('/client/jobs'),
      onActiveJobPressed: (jobId) => context.push('/client/job/$jobId'),
      onRefresh: () {
        ref.invalidate(myPreviousWorkersProvider);
        return refreshClientJobs(ref);
      },
    );
  }

  /// "Pedir de novo" a partir de "Os teus jardineiros": o pedido de origem
  /// é o último trabalho concluído com esse jardineiro.
  Future<void> _repeatHire(
    BuildContext context,
    WidgetRef ref,
    PreviousWorker worker,
  ) async {
    final toast = AppToast.of(context);
    JobRequest? source = ref
        .read(clientJobsProvider)
        .asData
        ?.value
        .where((j) => j.id == worker.lastJobId)
        .firstOrNull;
    if (source == null) {
      try {
        source = await ref.read(jobByIdProvider(worker.lastJobId).future);
      } catch (e) {
        toast.error(friendlyError(e));
        return;
      }
    }
    if (!context.mounted) return;
    if (source == null) {
      toast.error('Não foi possível abrir o último trabalho. Tenta novamente.');
      return;
    }
    await startRepeatHire(
      context,
      ref,
      sourceJob: source,
      workerName: worker.workerName,
      workerAvatarUrl: worker.workerAvatarUrl,
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
