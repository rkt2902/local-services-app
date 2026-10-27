import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/phone_utils.dart';
import '../../../core/constants/enums.dart';
import '../../../core/router/app_back_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/address_map_link.dart';
import '../../../core/widgets/app_whatsapp_button.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/bottom_actions_bar.dart';
import '../../../core/widgets/photo_viewer_screen.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../../core/widgets/job_flow_stepper.dart';
import '../../../core/widgets/app_tab_header.dart';
import '../../../core/widgets/user_avatar_with_name.dart';
import '../../auth/application/auth_providers.dart';
import '../../help_requests/application/help_request_providers.dart';
import '../../help_requests/data/help_request_model.dart';
import '../../proposals/application/proposal_price_labels.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../ratings/application/rating_providers.dart';
import '../../worker/application/worker_providers.dart';
import '../application/job_providers.dart';
import '../application/job_labels.dart';
import '../application/client_job_flow.dart';
import '../../../core/utils/price_labels.dart';
import '../data/job_model.dart';
import 'widgets/cancel_job_dialog.dart';
import 'widgets/reschedule_dialog.dart';
import '../../../core/widgets/app_toast.dart';

/// Ecrã dedicado ao pedido `confirmed` — extraído de
/// `client_job_detail_screen.dart` (doc.txt, "7b. Detalhe do pedido
/// agendado/confirmado"). `client_job_detail_screen.dart` delega para aqui
/// sem mudar de rota quando `job.status == JobStatus.confirmed`.
class ClientScheduledJobDetailScreen extends ConsumerStatefulWidget {
  const ClientScheduledJobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<ClientScheduledJobDetailScreen> createState() =>
      _ClientScheduledJobDetailScreenState();
}

class _ClientScheduledJobDetailScreenState
    extends ConsumerState<ClientScheduledJobDetailScreen> {
  bool _saving = false;
  bool _proposingReschedule = false;
  bool _respondingReschedule = false;
  final Set<String> _approvingHelp = {};

  /// Separador aberto: 0 Resumo, 1 Equipa (design A12).
  int _tab = 0;

  Future<void> _cancelJob() async {
    final result = await CancelJobDialog.show(context, isClient: true);
    if (result == null || !mounted) return;

    final wantsReopen = await AppConfirmDialog.show(
      context,
      icon: Icons.replay_rounded,
      title: 'Voltar a publicar?',
      message: 'Queres voltar a publicar este pedido para encontrar outro '
          'jardineiro?',
      confirmLabel: 'Sim',
      cancelLabel: 'Não',
    );
    // Fechar o diálogo sem responder (toque fora, voltar) é desistir, não
    // "Não": antes cancelava na mesma.
    if (wantsReopen == null || !mounted) return;

    setState(() => _saving = true);
    final toast = AppToast.of(context);
    final router = GoRouter.of(context);
    var navigatedAway = false;
    try {
      final newJobId = await ref.read(jobRepositoryProvider).cancelJob(
            jobId: widget.jobId,
            reason: result['reason']!,
            reasonDetail: result['reasonDetail'],
            clientWantsReopen: wantsReopen,
          );
      navigatedAway = true;
      router.go('/client/jobs');
      if (newJobId != null) {
        toast.show('Pedido cancelado e reaberto para encontrar outro jardineiro.');
      } else {
        toast.show('Pedido cancelado.');
      }
      ref.invalidate(clientJobsProvider);
      ref.invalidate(jobByIdProvider(widget.jobId));
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      if (!navigatedAway && mounted) setState(() => _saving = false);
    }
  }

  Future<void> _proposeReschedule() async {
    final result = await RescheduleDialog.show(context);
    if (result == null || !mounted) return;

    setState(() => _proposingReschedule = true);
    final toast = AppToast.of(context);
    try {
      await ref.read(jobRepositoryProvider).proposeReschedule(
            jobId: widget.jobId,
            newDate: result['date'] as DateTime,
            newTime: result['time'] as String?,
            newFlexible: result['flexible'] as bool,
          );
      ref.invalidate(clientJobsProvider);
      ref.invalidate(jobByIdProvider(widget.jobId));
      toast.show('Remarcação enviada.');
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      if (mounted) setState(() => _proposingReschedule = false);
    }
  }

  Future<void> _acceptReschedule() async {
    if (_respondingReschedule) return;
    setState(() => _respondingReschedule = true);
    final toast = AppToast.of(context);
    try {
      await ref.read(jobRepositoryProvider).acceptReschedule(widget.jobId);
      ref.invalidate(clientJobsProvider);
      ref.invalidate(jobByIdProvider(widget.jobId));
      toast.show('Nova data aceite.');
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      if (mounted) setState(() => _respondingReschedule = false);
    }
  }

  Future<void> _rejectReschedule() async {
    if (_respondingReschedule) return;
    setState(() => _respondingReschedule = true);
    final toast = AppToast.of(context);
    try {
      await ref.read(jobRepositoryProvider).rejectReschedule(widget.jobId);
      ref.invalidate(clientJobsProvider);
      ref.invalidate(jobByIdProvider(widget.jobId));
      toast.show('Remarcação recusada.');
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      if (mounted) setState(() => _respondingReschedule = false);
    }
  }

  Future<void> _approveHelpRequests(List<HelpRequest> requests) async {
    final ids = [for (final hr in requests) hr.id];
    if (ids.isEmpty) return;
    setState(() => _approvingHelp.addAll(ids));
    final toast = AppToast.of(context);
    try {
      final repo = ref.read(helpRequestRepositoryProvider);
      for (final id in ids) {
        await repo.approveHelpRequest(id);
      }
      toast.show('Aprovado. O jardineiro pode agora procurar ajudantes.');
      ref.invalidate(helpRequestsForJobProvider(widget.jobId));
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      if (mounted) setState(() => _approvingHelp.removeAll(ids));
    }
  }

  Future<void> _openWhatsApp(String phone) =>
      openWhatsAppOrWarn(context, phone);

  @override
  Widget build(BuildContext context) {
    return ref.watch(jobByIdProvider(widget.jobId)).when(
      loading: () => Scaffold(
        backgroundColor: AppColors.background,
        body: _ScheduledLoading(onBack: () => goBackOrToRoleHome(context)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        body: _ScheduledError(
          onBack: () => goBackOrToRoleHome(context),
          onRetry: () => ref.invalidate(jobByIdProvider(widget.jobId)),
        ),
      ),
      data: (job) {
        if (job == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: _ScheduledError(
              onBack: () => goBackOrToRoleHome(context),
              onRetry: null,
            ),
          );
        }

        final theme = Theme.of(context);
        final currentUserId = ref.watch(currentUserIdProvider);
        final acceptedProposalAsync = ref.watch(acceptedProposalForJobProvider(widget.jobId));
        final photosAsync = ref.watch(jobPhotosProvider(widget.jobId));
        final workerId = acceptedProposalAsync.asData?.value?.workerId ?? '';
        final workerInfoAsync = ref.watch(workerBasicInfoProvider(workerId));
        final ratingAsync = ref.watch(ratingSummaryProvider(workerId));
        final serviceTypes = ref.watch(serviceTypesProvider).asData?.value ?? const [];
        final pendingHelpRequests = (ref
                .watch(helpRequestsForJobProvider(widget.jobId))
                .asData
                ?.value ??
            const [])
            .where((hr) => hr.status == HelpRequestStatus.pendingApproval)
            .toList();
        // 0055: o cliente vê quem vem ajudar (nome e foto).
        final team =
            ref.watch(acceptedHelpersForJobProvider(widget.jobId)).asData?.value ??
                const <AcceptedHelper>[];

        final serviceLabel = serviceTypes
                .where((s) => s.id == job.serviceTypeId)
                .map((s) => s.name)
                .firstOrNull ??
            '—';
        final workerPhone = workerInfoAsync.asData?.value['phone'] ?? '';

        // Mesmas regras do servidor (`cancel_job`, `propose_reschedule`):
        // compara datas, só até à véspera do trabalho; e nada disto
        // enquanto houver uma remarcação por responder.
        final reschedulePending =
            job.rescheduleStatus == RescheduleStatus.pending;
        final onOrAfterJobDay =
            isOnOrAfterJobDay(job.confirmedDate, DateTime.now());
        final canReschedule =
            !_proposingReschedule && !reschedulePending && !onOrAfterJobDay;
        final canCancel = !_saving && !reschedulePending && !onOrAfterJobDay;
        final String? actionsNotice = reschedulePending
            ? 'Enquanto houver uma remarcação por responder não podes '
                'cancelar nem remarcar.'
            : onOrAfterJobDay
                ? 'Cancelar e remarcar só é possível até à véspera do trabalho.'
                : null;

        Widget? rescheduleIncomingBanner;
        if (job.rescheduleStatus == RescheduleStatus.pending &&
            job.rescheduleProposedBy != null &&
            job.rescheduleProposedBy != currentUserId) {
          final dateStr = job.rescheduleProposedDate != null
              ? DateFormat('dd/MM/yyyy').format(job.rescheduleProposedDate!)
              : '—';
          final timeStr = job.rescheduleProposedFlexible == true
              ? '(horário flexível)'
              : (job.rescheduleProposedTime != null ? 'às ${job.rescheduleProposedTime}' : '');
          rescheduleIncomingBanner = Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppStatusColor.waiting.background,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Icon(Icons.event_repeat, color: AppStatusColor.waiting.foreground, size: 20),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'O jardineiro propôs remarcar para $dateStr $timeStr'.trim(),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppStatusColor.waiting.foreground),
                    ),
                  ),
                ]),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _respondingReschedule ? null : _acceptReschedule,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.input),
                          ),
                        ),
                        child: const Text('Aceitar nova data'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _respondingReschedule ? null : _rejectReschedule,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.divider),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.input),
                          ),
                        ),
                        child: const Text('Recusar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        Widget? rescheduleOutgoingNotice;
        if (job.rescheduleStatus == RescheduleStatus.pending &&
            job.rescheduleProposedBy == currentUserId) {
          rescheduleOutgoingNotice = Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppStatusColor.waiting.background,
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
            child: Row(
              children: [
                Icon(Icons.hourglass_top, color: AppStatusColor.waiting.foreground, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'À espera de resposta à remarcação que propuseste.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppStatusColor.waiting.foreground),
                  ),
                ),
              ],
            ),
          );
        }

        final photosWidget = photosAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => const SizedBox.shrink(),
          data: (urls) {
            if (urls.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fotos',
                    style: theme.textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: urls.length,
                      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PhotoViewerScreen(photoUrls: urls, initialIndex: i),
                        )),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                          child: Image.network(urls[i], width: 72, height: 72, cacheWidth: 300, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );

        final proposal = acceptedProposalAsync.asData?.value;
        final fixed = proposal?.isFixedTotal ?? false;
        final priceLabel = proposal == null
            ? '—'
            : fixed
                ? compactMoneyLabel(proposal.totalPrice!)
                : acceptedProposalPriceLabel(proposal);
        // Valor fechado: o que inclui (design A6, F).
        final includeOptions = fixed
            ? ref.watch(proposalIncludeOptionsProvider).asData?.value ??
                const []
            : const [];
        final includesLabel = fixed
            ? proposalIncludesSummaryLabel(proposal!, [...includeOptions])
            : null;
        final durationLabel =
            proposal == null ? '' : proposalDurationLabel(proposal);
        // "Dia 2 de 3" com o trabalho em curso em vários dias.
        final workDays = (proposal != null && job.isInProgress)
            ? ref.watch(jobWorkDaysProvider(job.id)).asData?.value ?? const []
            : const [];
        final workDayLabel = proposal != null &&
                workDays.isNotEmpty &&
                isMultiDayWork(proposal, dayCount: workDays.length)
            ? workDayHeaderLabel(
                workDays.last.dayNumber, plannedWorkDays(proposal))
            : null;

        final workerName = workerInfoAsync.asData?.value['full_name'] ?? '';
        final helpRequests =
            ref.watch(helpRequestsForJobProvider(widget.jobId)).asData?.value ??
                const <HelpRequest>[];
        final flowTeam = clientJobTeam(
          proposalPeopleNeeded: proposal?.peopleNeeded,
          helpRequests: helpRequests,
          helperNames: [
            for (final h in team) h.fullName == '—' ? '' : h.fullName,
          ],
        );
        final stage = clientJobFlowStage(job, flowTeam);
        final banner = clientJobFlowBanner(
          job: job,
          team: flowTeam,
          workerName: workerName,
        );
        final approving = pendingHelpRequests
            .any((hr) => _approvingHelp.contains(hr.id));
        Widget? bannerWidget(int entrance) => banner == null
            ? null
            : AppStaggeredEntrance(
                index: entrance,
                child: _FlowBanner(
                  banner: banner,
                  approving: approving,
                  onApprove: banner.kind == ClientJobFlowBannerKind.approveTeam
                      ? () => _approveHelpRequests(pendingHelpRequests)
                      : null,
                ),
              );

        final summaryTab = ListView(
          key: const PageStorageKey('client-job-summary'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          children: [
            if (job.reopenedFrom != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Este pedido foi criado automaticamente após o cancelamento '
                        'de um pedido anterior.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.primaryPressed),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (rescheduleIncomingBanner != null) ...[
              rescheduleIncomingBanner,
              const SizedBox(height: AppSpacing.md),
            ],
            if (banner != null) ...[
              bannerWidget(0)!,
              const SizedBox(height: AppSpacing.md),
            ],
            AppStaggeredEntrance(
              index: 1,
              child: _WorkerContactCard(
                workerInfoAsync: workerInfoAsync,
                ratingAsync: ratingAsync,
                onOpenWhatsApp: () => _openWhatsApp(workerPhone),
              ),
            ),
            if (rescheduleOutgoingNotice != null) ...[
              const SizedBox(height: AppSpacing.sm),
              rescheduleOutgoingNotice,
            ],
            const SizedBox(height: AppSpacing.md),
            AppStaggeredEntrance(
              index: 2,
              child: _ScheduledSummary(
                serviceLabel: serviceLabel,
                dateTimeLabel: _scheduleLabel(job),
                addressLabel: job.addressText.isNotEmpty
                    ? job.addressText
                    : 'Localização não especificada',
                peopleLabel: flowTeam.hasHelpers
                    ? clientTeamSummaryLabel(flowTeam, workerName)
                    : null,
                priceLabel: priceLabel,
                priceRowLabel: fixed ? 'Valor fechado' : 'Valor acordado',
                durationLabel: durationLabel.isEmpty ? null : durationLabel,
                workDayLabel: workDayLabel,
                includesLabel: includesLabel == null
                    ? null
                    : 'Inclui ${includesLabel[0].toLowerCase()}${includesLabel.substring(1)}',
                fixedNote:
                    fixed ? 'Não muda com as horas nem com os dias.' : null,
              ),
            ),
            if (job.locationLat != 0 || job.locationLng != 0) ...[
              const SizedBox(height: AppSpacing.sm),
              AddressMapLink(
                address: job.addressText,
                lat: job.locationLat,
                lng: job.locationLng,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: AppSpacing.md),
            AppStaggeredEntrance(
              index: 3,
              child: _Description(description: job.description),
            ),
            photosWidget,
          ],
        );

        final teamTab = ListView(
          key: const PageStorageKey('client-job-team'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          children: [
            if (banner != null) ...[
              bannerWidget(0)!,
              const SizedBox(height: AppSpacing.md),
            ],
            const _SectionLabel('Responsável'),
            const SizedBox(height: AppSpacing.xs),
            AppStaggeredEntrance(
              index: 1,
              child: _TeamCard(
                child: _WorkerContactCard(
                  workerInfoAsync: workerInfoAsync,
                  ratingAsync: ratingAsync,
                  onOpenWhatsApp: () => _openWhatsApp(workerPhone),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (flowTeam.hasHelpers) ...[
              _SectionLabel(clientTeamHelpersHeading(flowTeam)),
              const SizedBox(height: AppSpacing.xs),
              if (team.isNotEmpty)
                AppStaggeredEntrance(
                  index: 2,
                  child: _TeamCard(
                    child: Column(
                      children: [
                        for (var i = 0; i < team.length; i++) ...[
                          if (i > 0)
                            const Divider(height: AppSpacing.md, color: AppColors.divider),
                          UserAvatarWithName(
                            name: team[i].fullName == '—' ? '' : team[i].fullName,
                            avatarUrl: team[i].avatarUrl,
                            radius: 18,
                            fallbackLabel: 'Ajudante',
                            nameStyle: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              if (flowTeam.joined < flowTeam.helpersNeeded) ...[
                if (team.isNotEmpty) const SizedBox(height: AppSpacing.sm),
                AppStaggeredEntrance(
                  index: 3,
                  child: _EmptyHelpers(label: clientTeamSearchingLabel(flowTeam)),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Os ajudantes vêm com o responsável. Qualquer dúvida, fala com ele.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ],
        );

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              children: [
                AppBackHeader(
                  title: serviceLabel,
                  subtitle: clientJobFlowSubtitle(
                    job: job,
                    workerName: workerName,
                  ),
                  onBack: () => goBackOrToRoleHome(context),
                  // Sem ajudantes não há fase Equipa nem separador Equipa
                  // (pedido do Henrique, 27/10): só o resumo.
                  bottom: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      JobFlowStepper(
                        stage: stage,
                        showTeam: flowTeam.hasHelpers,
                      ),
                      if (flowTeam.hasHelpers)
                        AppTabs(
                          items: [
                            const AppTabItem(label: 'Resumo'),
                            AppTabItem(label: 'Equipa', badge: flowTeam.countLabel),
                          ],
                          selectedIndex: _tab,
                          onSelected: (i) => setState(() => _tab = i),
                        )
                      else
                        const SizedBox(height: AppSpacing.xs),
                    ],
                  ),
                ),
                Expanded(
                  child: flowTeam.hasHelpers
                      ? IndexedStack(
                          index: _tab,
                          children: [summaryTab, teamTab],
                        )
                      : summaryTab,
                ),
                BottomActionsBar(children: [
                  PrimaryActionButton(
                    label: 'Falar por WhatsApp',
                    icon: appWhatsAppIcon,
                    onPressed: workerPhone.isEmpty ? null : () => _openWhatsApp(workerPhone),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: canReschedule ? _proposeReschedule : null,
                        child: Text(
                          'Remarcar',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: canReschedule
                                ? AppColors.primary
                                : AppStatusColor.neutral.foreground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      TextButton(
                        onPressed: canCancel ? _cancelJob : null,
                        child: Text(
                          'Cancelar pedido',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: canCancel
                                ? AppStatusColor.cancelled.foreground
                                : AppStatusColor.neutral.foreground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (actionsNotice != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      actionsNotice,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _scheduleLabel(JobRequest job) {
  if (job.confirmedDate == null) return 'A combinar';
  final date = DateFormat('dd/MM/yyyy').format(job.confirmedDate!);
  if (job.confirmedFlexible) return '$date (horário flexível)';
  final time = job.confirmedTime;
  if (time != null) {
    return '$date às ${time.length >= 5 ? time.substring(0, 5) : time}';
  }
  return date;
}

class _WorkerContactCard extends StatelessWidget {
  const _WorkerContactCard({
    required this.workerInfoAsync,
    required this.ratingAsync,
    required this.onOpenWhatsApp,
  });

  final AsyncValue<Map<String, String>> workerInfoAsync;
  final AsyncValue<RatingSummary> ratingAsync;
  final VoidCallback onOpenWhatsApp;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return workerInfoAsync.when(
      loading: () => AppSkeletonShimmer(
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
        ),
      ),
      error: (e, _) => const Text('Não foi possível carregar o contacto.'),
      data: (info) {
        final name = info['full_name'] ?? '';
        final phone = info['phone'] ?? '';
        final avatarUrl = info['avatar_url'];
        final rating = ratingAsync.asData?.value;
        final ratingLabel = rating != null && rating.ratingCount > 0
            ? '★ ${decimalLabel(rating.avgRating, 1)} (${rating.ratingCount})'
            : 'Sem avaliações ainda';

        return Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primaryContainer,
              backgroundImage:
                  (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
              child: (avatarUrl == null || avatarUrl.isEmpty)
                  ? const Icon(Icons.person_outline_rounded, color: AppColors.primary)
                  : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Jardineiro' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
                  ),
                  Text(ratingLabel, style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              onPressed: phone.isEmpty ? null : onOpenWhatsApp,
              tooltip: 'Falar por WhatsApp',
              icon: const Icon(appWhatsAppIcon, color: AppColors.whatsapp),
            ),
          ],
        );
      },
    );
  }
}

/// Aviso do topo do Resumo e da Equipa (design A12, C4 a C7). Cor pelo
/// momento: em curso e equipa completa a verde, à espera da cliente a
/// amarelo, equipa a formar a azul.
class _FlowBanner extends StatelessWidget {
  const _FlowBanner({
    required this.banner,
    required this.approving,
    this.onApprove,
  });

  final ClientJobFlowBanner banner;
  final bool approving;

  /// Só no pedido de ajudantes por aprovar.
  final VoidCallback? onApprove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (tone, icon) = switch (banner.kind) {
      ClientJobFlowBannerKind.started => (
          AppStatusColor.success,
          Icons.play_circle_outline_rounded,
        ),
      ClientJobFlowBannerKind.approveTeam => (
          AppStatusColor.waiting,
          Icons.group_add_outlined,
        ),
      ClientJobFlowBannerKind.formingTeam => (
          AppStatusColor.info,
          Icons.group_add_outlined,
        ),
      ClientJobFlowBannerKind.teamReady => (
          AppStatusColor.success,
          Icons.groups_outlined,
        ),
    };
    final body = banner.body;
    final onApprove = this.onApprove;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: tone.foreground, size: 22),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: banner.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (body != null) TextSpan(text: '\n$body'),
                    ],
                  ),
                  style: textTheme.bodyMedium?.copyWith(color: tone.foreground),
                ),
              ),
            ],
          ),
          if (onApprove != null) ...[
            const SizedBox(height: AppSpacing.sm),
            PrimaryActionButton(
              label: 'Aprovar',
              icon: Icons.check_rounded,
              isLoading: approving,
              onPressed: approving ? null : onApprove,
            ),
          ],
        ],
      ),
    );
  }
}

/// "RESPONSÁVEL", "AJUDANTES · 1 DE 2".
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: child,
    );
  }
}

/// Vagas por preencher ("À procura de 2 ajudantes").
class _EmptyHelpers extends StatelessWidget {
  const _EmptyHelpers({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.agendaDashed),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

class _ScheduledSummary extends StatelessWidget {
  const _ScheduledSummary({
    required this.serviceLabel,
    required this.dateTimeLabel,
    required this.addressLabel,
    required this.priceLabel,
    this.peopleLabel,
    this.priceRowLabel = 'Valor acordado',
    this.durationLabel,
    this.workDayLabel,
    this.includesLabel,
    this.fixedNote,
  });

  final String serviceLabel;
  final String dateTimeLabel;
  final String addressLabel;
  final String priceLabel;
  final String? peopleLabel;

  /// "Valor fechado" numa proposta com valor total.
  final String priceRowLabel;
  final String? durationLabel;

  /// "Dia 2 de 3", com o trabalho em curso em vários dias.
  final String? workDayLabel;

  /// "Inclui material, remoção de resíduos".
  final String? includesLabel;

  /// "Não muda com as horas nem com os dias."
  final String? fixedNote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _SummaryRow(label: 'Serviço', value: serviceLabel),
          const SizedBox(height: AppSpacing.sm),
          _SummaryRow(label: 'Data e hora', value: dateTimeLabel),
          const SizedBox(height: AppSpacing.sm),
          _SummaryRow(label: 'Morada', value: addressLabel),
          if (peopleLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _SummaryRow(label: 'Equipa', value: peopleLabel!),
          ],
          if (durationLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _SummaryRow(label: 'Duração prevista', value: durationLabel!),
          ],
          if (workDayLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _SummaryRow(label: 'Hoje', value: workDayLabel!),
          ],
          const SizedBox(height: AppSpacing.sm),
          const Divider(color: AppColors.divider),
          const SizedBox(height: AppSpacing.sm),
          _SummaryRow(label: priceRowLabel, value: priceLabel, emphasized: true),
          if (includesLabel != null || fixedNote != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                [?includesLabel, ?fixedNote].join('. '),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.emphasized = false});

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
        ),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: textTheme.bodyMedium?.copyWith(
              color: emphasized ? AppColors.primary : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _Description extends StatelessWidget {
  const _Description({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Descrição', style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.xs),
        Text(description, style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary)),
      ],
    );
  }
}

class _ScheduledLoading extends StatelessWidget {
  const _ScheduledLoading({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _LoadingHeader(onBack: onBack),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, index) => AppSkeletonShimmer(
                child: Container(
                  height: index == 0 ? 88 : 76,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingHeader extends StatelessWidget {
  const _LoadingHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Voltar',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: AppSkeletonShimmer(
              child: Container(
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduledError extends StatelessWidget {
  const _ScheduledError({required this.onBack, required this.onRetry});

  final VoidCallback onBack;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Column(
        children: [
          _LoadingHeader(onBack: onBack),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Não foi possível carregar o pedido.',
                      textAlign: TextAlign.center,
                      style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton(onPressed: onRetry, child: const Text('Tentar novamente')),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
