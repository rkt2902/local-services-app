import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/router/app_back_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/theme/app_status_presentation.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../../core/widgets/service_icon.dart';
import '../../auth/application/auth_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';
import '../application/worker_job_rules.dart';
import '../application/worker_providers.dart';
import 'widgets/worker_job_detail_view.dart' as view;
import 'worker_my_job_detail_screen.dart' as my_job;

/// Detalhe de uma oportunidade ("Pedidos disponíveis" → detalhe).
///
/// Wrapper que liga os providers reais ao componente apresentacional em
/// widgets/worker_job_detail_view.dart.
class WorkerJobDetailScreen extends ConsumerWidget {
  const WorkerJobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobAsync = ref.watch(jobByIdProvider(jobId));

    return jobAsync.when(
      loading: () => const Scaffold(
        body: AppScreenLoadingSkeleton(),
      ),
      error: (e, _) => _MessageScaffold(
        child: Text(
          friendlyError(e),
          textAlign: TextAlign.center,
        ),
      ),
      data: (job) {
        // get_job_by_id (0043) não devolve nada a quem já não pode ver o
        // pedido: deixou de estar aberto e o worker não tinha proposta.
        if (job == null) {
          return const _MessageScaffold(child: view.WorkerJobUnavailableBanner());
        }
        return _buildDetail(context, ref, job);
      },
    );
  }

  Widget _buildDetail(BuildContext context, WidgetRef ref, JobRequest job) {
    // Pedido já confirmado com este worker (ex.: aberto por uma notificação
    // antiga de "novo pedido"): mostra o ecrã do trabalho, com morada exata,
    // mapa e valor acordado, em vez da oportunidade ("Preço a combinar").
    final unavailable = job.status != JobStatus.open;
    if (unavailable) {
      final myId = ref.watch(currentUserIdProvider) ?? '';
      final acceptedAsync = ref.watch(acceptedProposalForJobProvider(jobId));
      // Espera pela proposta aceite para não piscar "já não está
      // disponível" ao próprio worker aceite.
      if (acceptedAsync.isLoading) {
        return const Scaffold(body: AppScreenLoadingSkeleton());
      }
      final accepted = acceptedAsync.asData?.value;
      if (accepted != null && myId.isNotEmpty && accepted.workerId == myId) {
        return my_job.WorkerMyJobDetailScreen(
          proposalId: accepted.id,
          jobId: jobId,
        );
      }
    }

    final serviceTypes = ref.watch(serviceTypesProvider).asData?.value ?? [];
    final workerProfile = ref.watch(workerProfileProvider).asData?.value;
    final photos = ref.watch(jobPhotosProvider(jobId)).asData?.value ?? [];
    final clientInfo = ref.watch(openJobClientIdentityProvider(jobId)).asData?.value;

    final currentUserId = ref.watch(currentUserIdProvider) ?? '';
    final workerProposalAsync = currentUserId.isEmpty
        ? const AsyncValue<JobProposal?>.data(null)
        : ref.watch(workerProposalForJobProvider((jobId, currentUserId)));
    final myPendingProposal =
        unavailable ? null : workerProposalAsync.asData?.value;

    final serviceType =
        serviceTypes.where((s) => s.id == job.serviceTypeId).firstOrNull;

    var distanceLabel = '';
    if (workerProfile != null) {
      final meters = Geolocator.distanceBetween(
        workerProfile.baseLat,
        workerProfile.baseLng,
        job.locationLat,
        job.locationLng,
      );
      distanceLabel = meters < 1000
          ? '${meters.round()} m'
          : '${(meters / 1000).toStringAsFixed(1)} km';
    }

    AppStatusPresentation? badge;
    if (unavailable) {
      badge = null;
    } else if (job.urgency == Urgency.urgent) {
      badge = urgentStatusPresentation;
    } else if (DateTime.now().difference(job.createdAt).inHours < 24) {
      badge = const AppStatusPresentation(
        label: 'Novo',
        color: AppStatusColor.success,
      );
    }

    final avatarUrl = clientInfo?['avatar_url'];

    final data = view.WorkerJobDetailViewData(
      id: job.id,
      title: serviceType?.name ?? '',
      // Oportunidade: o servidor só manda a localidade (migration 0043).
      locationLabel: job.addressText.isNotEmpty
          ? '${job.addressText} · morada exata depois de aceite'
          : 'Localização não especificada',
      distanceLabel: distanceLabel,
      deadlineLabel: jobDeadlineLabel(job.dateMode, job.preferredDate),
      areaLabel: _areaLabel(job),
      // O MVP não tem orçamento no pedido (só nasce quando um worker
      // propõe) — mesma decisão já usada no dashboard e na lista de
      // pedidos disponíveis.
      budgetLabel: 'Preço a combinar',
      description: job.description,
      serviceIcon: serviceIconFor(serviceType?.icon),
      clientName: clientInfo?['full_name'] ?? '',
      clientAvatar: (avatarUrl != null && avatarUrl.isNotEmpty)
          ? avatarUrl
          : null,
      photos: photos.map((url) => NetworkImage(url) as ImageProvider).toList(),
      badge: badge,
    );

    return view.WorkerJobDetailScreen(
      data: data,
      onBack: () => goBackOrToRoleHome(context),
      unavailable: unavailable,
      unavailableReason: jobUnavailableReason(
        job.status,
        cancelReason: job.cancelReason,
      ),
      onViewMyProposalPressed: myPendingProposal == null
          ? null
          : () => context.push(
                '/worker/my-job/${myPendingProposal.id}?jobId=$jobId',
              ),
      onSendProposalPressed: () => context.push('/worker/job/$jobId/propose'),
    );
  }
}

/// Ecrã inteiro só com uma mensagem (erro ou pedido indisponível), sempre
/// com voltar (fallback para a home quando aberto por notificação).
class _MessageScaffold extends StatelessWidget {
  const _MessageScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: const AppBackButton(),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: AppStaggeredEntrance(index: 0, child: child),
          ),
        ),
      ),
    );
  }
}

String _areaLabel(JobRequest job) => job.sizeEstimate?.label ?? 'Não especificado';
