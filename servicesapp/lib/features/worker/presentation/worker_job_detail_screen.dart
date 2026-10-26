import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/price_labels.dart';
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
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../../core/widgets/service_icon.dart';
import '../../agenda/application/agenda_conflicts.dart';
import '../../agenda/application/agenda_providers.dart';
import '../../agenda/data/agenda_entry_model.dart';
import '../../agenda/presentation/agenda_day_preview.dart';
import '../../agenda/presentation/agenda_day_preview_view_data.dart';
import '../../agenda/presentation/agenda_slot_check.dart';
import '../../auth/application/auth_providers.dart';
import '../../jobs/application/job_labels.dart';
import '../../jobs/application/direct_request_labels.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';
import '../application/worker_job_rules.dart';
import '../application/worker_providers.dart';
import 'widgets/worker_direct_request_card.dart' as view;
import 'widgets/worker_job_detail_view.dart' as view;
import 'worker_my_job_detail_screen.dart' as my_job;

/// Detalhe de uma oportunidade ("Pedidos disponíveis" → detalhe).
///
/// Wrapper que liga os providers reais ao componente apresentacional em
/// widgets/worker_job_detail_view.dart.
class WorkerJobDetailScreen extends ConsumerStatefulWidget {
  const WorkerJobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<WorkerJobDetailScreen> createState() =>
      _WorkerJobDetailScreenState();
}

class _WorkerJobDetailScreenState extends ConsumerState<WorkerJobDetailScreen> {
  String get jobId => widget.jobId;

  /// "Não posso desta vez" (pedido direto, 0057) a correr.
  bool _decliningDirect = false;

  /// Depois de recusar, o servidor deixa de mostrar o pedido a este
  /// jardineiro: o ecrã fica com o painel "Avisámos..." até sair por "Ver
  /// outras oportunidades", sem recarregar o pedido.
  String? _declinedMessage;

  Future<void> _declineDirect(String clientName, bool autoRelease) async {
    final name = firstNameOr(clientName, 'o cliente');
    // Com o interruptor do cliente desligado (0059) o pedido fica parado e
    // é o cliente que decide.
    final next = autoRelease
        ? 'o pedido fica visível para outros jardineiros'
        : '$name decide se mostra o pedido a outros jardineiros';
    final confirmed = await AppConfirmDialog.show(
      context,
      icon: Icons.event_busy_outlined,
      title: 'Não podes desta vez?',
      message: 'Avisamos $name e $next. Não dá para desfazer.',
      confirmLabel: 'Não posso',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _decliningDirect = true);
    final toast = AppToast.of(context);
    try {
      await ref.read(jobRepositoryProvider).declineDirectJobRequest(jobId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _decliningDirect = false);
      toast.error(friendlyError(e));
      return;
    }
    if (!mounted) return;
    setState(() {
      _decliningDirect = false;
      _declinedMessage = autoRelease
          ? 'Avisámos $name. O pedido fica visível para os outros jardineiros.'
          : 'Avisámos $name. $name decide se mostra o pedido a outros '
              'jardineiros.';
    });
    // Este ecrã não observa a lista: pode recarregar já.
    ref.invalidate(jobsInRadiusProvider);
  }

  void _seeOtherJobs() {
    // T4: navegar e só depois invalidar o pedido que este ecrã observa.
    context.go('/worker/available-jobs');
    ref.invalidate(jobByIdProvider(jobId));
  }

  @override
  Widget build(BuildContext context) {
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
        return _buildDetail(context, job);
      },
    );
  }

  Widget _buildDetail(BuildContext context, JobRequest job) {
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
          : '${decimalLabel(meters / 1000, 1)} km';
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
    final clientName = clientInfo?['full_name'] ?? '';

    // Pedido direto para mim (0057, 0059): à espera da minha resposta, ou
    // parado depois do prazo à espera do cliente (ainda posso propor).
    final directUntil = job.directUntil;
    final directMine = !unavailable &&
        job.directWorkerId != null &&
        job.directWorkerId == currentUserId;
    final isDirectWaitingForMe = directMine && job.isDirectWaiting;
    final isDirectForMe =
        directMine && (job.isDirectWaiting || job.isDirectOnHold);
    final fromCard = job.directOrigin == DirectRequestOrigin.publicCard;
    final clientFirstName = firstNameOr(clientName, 'O cliente');

    view.WorkerDirectRequestViewData? direct;
    if (isDirectForMe || _declinedMessage != null) {
      // Pelo cartão não há trabalho anterior: sem histórico para pedir.
      final AsyncValue<view.WorkerDirectHistoryViewData?> history = fromCard
          ? const AsyncValue.data(null)
          : ref.watch(directRequestContextProvider(jobId)).whenData((history) {
              if (history == null) return null;
              final service = serviceTypes
                      .where((s) => s.id == history.serviceTypeId)
                      .map((s) => s.name)
                      .firstOrNull ??
                  '';
              final name = history.clientName.isNotEmpty
                  ? history.clientName
                  : clientName;
              return view.WorkerDirectHistoryViewData(
                clientInitial: initialOf(name.isEmpty ? 'Cliente' : name),
                clientAvatarUrl: (avatarUrl != null && avatarUrl.isNotEmpty)
                    ? avatarUrl
                    : null,
                label: directHistoryLabel(history, serviceLabel: service),
              );
            });
      String? outsideArea;
      if (workerProfile != null) {
        final meters = Geolocator.distanceBetween(
          workerProfile.baseLat,
          workerProfile.baseLng,
          job.locationLat,
          job.locationLng,
        );
        if (meters > workerProfile.radiusKm * 1000) {
          outsideArea = outsideAreaLabel(meters / 1000);
        }
      }
      direct = view.WorkerDirectRequestViewData(
        tagLabel: job.isDirectOnHold
            ? 'Pedido só para ti · prazo terminado'
            : directUntil == null
                ? 'Pedido só para ti'
                : 'Pedido só para ti · '
                    '${directTimeLeftLabel(directUntil, DateTime.now())}',
        titleLabel: fromCard
            ? '$clientFirstName pediu-te orçamento pelo teu cartão'
            : null,
        explanationLabel: !job.directAutoRelease
            ? 'Se não responderes a tempo, $clientFirstName decide se '
                'mostra o pedido a outros jardineiros.'
            : fromCard
                ? 'Se não responderes a tempo, o pedido pode ser mostrado '
                    'a outros jardineiros.'
                : 'O cliente pediu-te este trabalho primeiro. Se não '
                    'responderes a tempo, o pedido fica visível para todos.',
        outsideAreaLabel: outsideArea,
        noticeLabel: job.isDirectOnHold
            ? '$clientFirstName vai decidir se mostra o pedido a outros '
                'jardineiros. Ainda podes enviar proposta.'
            : null,
        history: history,
      );
    } else if (directMine &&
        job.directStatus == DirectRequestStatus.expired &&
        myPendingProposal == null) {
      // O prazo acabou com o interruptor ligado: aberto a todos, mas ainda
      // dá para propor.
      direct = const view.WorkerDirectRequestViewData(
        tagLabel: 'Prazo terminado',
        explanationLabel:
            'O pedido está aberto agora a todos. Ainda podes enviar proposta.',
        history: AsyncValue.data(null),
      );
    }

    final data = view.WorkerJobDetailViewData(
      id: job.id,
      title: serviceType?.name ?? '',
      // Oportunidade: o servidor só manda a localidade (migration 0043).
      locationLabel: job.addressText.isNotEmpty
          ? '${job.addressText} · morada exata depois de aceite'
          : 'Localização não especificada',
      distanceLabel: distanceLabel,
      deadlineLabel: jobDeadlineLabel(
        job.dateMode,
        job.preferredDate,
        availabilityText: job.availabilityText,
      ),
      areaLabel: _areaLabel(job),
      // O MVP não tem orçamento no pedido (só nasce quando um worker
      // propõe) — mesma decisão já usada no dashboard e na lista de
      // pedidos disponíveis.
      budgetLabel: 'Preço a combinar',
      description: job.description,
      serviceIcon: serviceIconFor(serviceType?.icon),
      clientName: clientName,
      clientAvatar: (avatarUrl != null && avatarUrl.isNotEmpty)
          ? avatarUrl
          : null,
      photos: photos.map((url) => NetworkImage(url) as ImageProvider).toList(),
      badge: badge,
    );

    // Chip da Agenda (A10, M2): só com um dia pedido e o pedido aberto.
    final requestDay = unavailable
        ? null
        : proposalInitialDate(job, DateTime.now());
    final agendaEntries = requestDay == null
        ? null
        : ref
            .watch(agendaRangeProvider(agendaMonthRange(requestDay)))
            .asData
            ?.value;
    final agendaAvailability = requestDay == null || agendaEntries == null
        ? null
        : agendaRequestAvailability(
            slot: AgendaSlot(date: requestDay),
            entries: agendaEntries,
          );

    return view.WorkerJobDetailScreen(
      data: data,
      agendaAvailability: agendaAvailability,
      onAgendaAvailabilityPressed: requestDay == null
          ? null
          : () => showAgendaDayPreview(
                context,
                day: requestDay,
                ghost: AgendaDayPreviewGhost(
                  date: requestDay,
                  label: 'O pedido',
                  slotKind: AgendaEntryKind.proposal,
                ),
              ),
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
      directRequest: direct,
      onRetryDirectHistory: () =>
          ref.invalidate(directRequestContextProvider(jobId)),
      // "Não posso desta vez" só enquanto a reserva corre.
      onDeclineDirectPressed:
          myPendingProposal == null && isDirectWaitingForMe
              ? () => _declineDirect(clientName, job.directAutoRelease)
              : null,
      decliningDirect: _decliningDirect,
      directDeclinedMessage: _declinedMessage,
      onSeeOtherJobsPressed: _seeOtherJobs,
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
