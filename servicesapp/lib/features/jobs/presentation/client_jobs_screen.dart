import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/date_labels.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../worker/application/worker_providers.dart';
import '../application/job_providers.dart';
import '../data/job_model.dart';
import 'widgets/client_jobs_view.dart' as view;

/// "Os meus pedidos" (cliente).
///
/// Wrapper que liga `clientJobsProvider`/`serviceTypesProvider` ao
/// componente apresentacional em widgets/client_jobs_view.dart — este
/// ficheiro é o único que fala com Supabase; o widget de apresentação não
/// sabe que Riverpod existe.
///
/// Nota de path: o documento de referência assumia
/// `features/client/presentation/client_jobs_screen.dart`; o ficheiro real
/// sempre viveu em `features/jobs/presentation/` (é aqui que o resto do
/// domínio de jobs do cliente já está — `client_job_detail_screen.dart`,
/// `client_job_confirmed_screen.dart`). Mantive o path real, só adaptei o
/// conteúdo.
class ClientJobsScreen extends ConsumerWidget {
  const ClientJobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(clientJobsProvider);
    final serviceTypesAsync = ref.watch(serviceTypesProvider);

    final AsyncValue<view.ClientJobsViewData> dataAsync = jobsAsync.when(
      loading: () => const AsyncValue.loading(),
      error: AsyncValue.error,
      data: (jobs) {
        if (serviceTypesAsync.isLoading) return const AsyncValue.loading();
        if (serviceTypesAsync.hasError) {
          return AsyncValue.error(
            serviceTypesAsync.error!,
            serviceTypesAsync.stackTrace ?? StackTrace.current,
          );
        }
        final serviceTypes = serviceTypesAsync.value ?? const <ServiceType>[];

        // Condições exatas de sempre — P-8-8 (jobs cancelados sem proposta
        // aceite ficam invisíveis nas duas tabs) é uma decisão de produto
        // pendente, não corrigida aqui.
        final activeJobs = jobs
            .where((j) =>
                j.status == JobStatus.open ||
                j.status == JobStatus.confirmed ||
                j.status == JobStatus.awaitingConfirmation)
            .toList();
        final historyJobs = jobs
            .where((j) =>
                j.status == JobStatus.completed ||
                j.status == JobStatus.noResponse ||
                (j.status == JobStatus.cancelled && j.acceptedProposalId != null))
            .toList();

        // Nome/foto do worker aceite — só existe depois de haver uma
        // proposta aceite (confirmed/awaitingConfirmation/completed).
        // Mesmo par de providers já usado (e já correto) em
        // client_job_detail_screen.dart/client_scheduled_job_detail_screen.dart;
        // esta lista simplesmente nunca os tinha chamado.
        const statusesWithWorker = {
          JobStatus.confirmed,
          JobStatus.awaitingConfirmation,
          JobStatus.completed,
        };

        view.ClientJobListItemViewData mapJob(JobRequest job) {
          final serviceName = serviceTypes
                  .where((t) => t.id == job.serviceTypeId)
                  .map((t) => t.name)
                  .firstOrNull ??
              'Desconhecido';

          String? workerName;
          String? workerAvatarUrl;
          if (statusesWithWorker.contains(job.status)) {
            final workerId = ref
                .watch(acceptedProposalForJobProvider(job.id))
                .asData
                ?.value
                ?.workerId;
            if (workerId != null && workerId.isNotEmpty) {
              final info =
                  ref.watch(workerBasicInfoProvider(workerId)).asData?.value;
              final name = info?['full_name'];
              if (name != null && name.isNotEmpty) workerName = name;
              final avatarUrl = info?['avatar_url'];
              if (avatarUrl != null && avatarUrl.isNotEmpty) {
                workerAvatarUrl = avatarUrl;
              }
            }
          }

          return view.ClientJobListItemViewData(
            jobId: job.id,
            title: serviceName,
            addressText: job.addressText,
            locationLat: job.locationLat,
            locationLng: job.locationLng,
            dateLabel: jobDeadlineLabel(job.dateMode, job.preferredDate),
            // Sem mapeamento por serviço — mesma decisão já usada em
            // worker_job_detail_screen.dart (o MVP não tem ícone por
            // categoria, só o genérico de jardinagem).
            serviceIcon: Icons.yard_outlined,
            statusPresentation:
                job.status.presentation(proposalCount: job.proposalCount),
            secondaryStatusPresentation: job.rescheduleStatus == RescheduleStatus.pending
                ? RescheduleStatus.pending.presentation
                : null,
            workerName: workerName,
            workerAvatarUrl: workerAvatarUrl,
          );
        }

        return AsyncValue.data(view.ClientJobsViewData(
          activeTabLabel: 'Ativos · ${activeJobs.length}',
          historyTabLabel: 'Histórico · ${historyJobs.length}',
          activeJobs: activeJobs.map(mapJob).toList(),
          historyJobs: historyJobs.map(mapJob).toList(),
        ));
      },
    );

    return view.ClientJobsScreen(
      dataAsync: dataAsync,
      onOpenJob: (jobId) => context.push('/client/job/$jobId'),
      onCreateJob: () => context.push('/client/create-job'),
      onRetry: () {
        ref.invalidate(clientJobsProvider);
        ref.invalidate(serviceTypesProvider);
      },
    );
  }
}
