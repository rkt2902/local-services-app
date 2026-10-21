import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/constants/enums.dart';
import '../../../core/router/app_back_navigation.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/price_labels.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../../core/widgets/photo_viewer_screen.dart';
import '../../auth/application/auth_providers.dart';
import '../../jobs/application/job_labels.dart';
import '../../jobs/application/job_timeline.dart';
import '../../client/application/client_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../../jobs/presentation/widgets/cancel_job_dialog.dart';
import '../../jobs/presentation/widgets/reschedule_dialog.dart';
import '../../help_requests/application/help_request_providers.dart';
import '../../help_requests/data/help_request_model.dart';
import '../application/worker_job_rules.dart';
import '../application/worker_list_invalidation.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../ratings/application/rating_providers.dart';
import 'widgets/mark_completed_sheet.dart';
import 'widgets/worker_my_job_detail_view.dart' as view;

class WorkerMyJobDetailScreen extends ConsumerStatefulWidget {
  const WorkerMyJobDetailScreen({
    super.key,
    required this.proposalId,
    required this.jobId,
  });

  final String proposalId;
  final String jobId;

  @override
  ConsumerState<WorkerMyJobDetailScreen> createState() =>
      _WorkerMyJobDetailScreenState();
}

class _WorkerMyJobDetailScreenState
    extends ConsumerState<WorkerMyJobDetailScreen> {
  bool _withdrawing = false;
  bool _cancellingJob = false;
  bool _proposingReschedule = false;
  bool _acceptingReschedule = false;
  bool _rejectingReschedule = false;

  /// Id do pedido: o da rota ou, se a rota veio sem `?jobId=` (link
  /// antigo/incompleto), o da própria proposta. Resolvido em [build].
  String _resolvedJobId = '';

  String get _jobId =>
      widget.jobId.isNotEmpty ? widget.jobId : _resolvedJobId;

  Future<void> _cancelJob() async {
    final result = await CancelJobDialog.show(context, isClient: false);
    if (result == null || !mounted) return;

    setState(() => _cancellingJob = true);
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final newJobId = await ref.read(jobRepositoryProvider).cancelJob(
            jobId: _jobId,
            reason: result['reason']!,
            reasonDetail: result['reasonDetail'],
          );
      // Regra T4: navegar → SnackBar → invalidar.
      router.go('/worker/home');
      scaffold.showSnackBar(SnackBar(
        content: Text(newJobId != null
            ? 'Pedido cancelado. O cliente foi notificado e o pedido foi reaberto.'
            : 'Pedido cancelado.'),
      ));
      invalidateWorkerLists(ref, jobId: _jobId);
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _cancellingJob = false);
    }
  }

  Future<void> _proposeReschedule() async {
    final result = await RescheduleDialog.show(context);
    if (result == null || !mounted) return;

    setState(() => _proposingReschedule = true);
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await ref.read(jobRepositoryProvider).proposeReschedule(
            jobId: _jobId,
            newDate: result['date'] as DateTime,
            newTime: result['time'] as String?,
            newFlexible: result['flexible'] as bool,
          );
      // Fica neste ecrã (sem pop: aberto por notificação não há nada para
      // fazer pop). SnackBar → invalidar.
      scaffold.showSnackBar(
          const SnackBar(content: Text('Remarcação enviada.')));
      invalidateWorkerLists(ref, jobId: _jobId);
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _proposingReschedule = false);
    }
  }

  Future<void> _acceptReschedule() async {
    setState(() => _acceptingReschedule = true);
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await ref.read(jobRepositoryProvider).acceptReschedule(_jobId);
      scaffold.showSnackBar(
          const SnackBar(content: Text('Nova data aceite.')));
      invalidateWorkerLists(ref, jobId: _jobId);
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _acceptingReschedule = false);
    }
  }

  Future<void> _rejectReschedule() async {
    setState(() => _rejectingReschedule = true);
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await ref.read(jobRepositoryProvider).rejectReschedule(_jobId);
      scaffold.showSnackBar(
          const SnackBar(content: Text('Remarcação recusada.')));
      invalidateWorkerLists(ref, jobId: _jobId);
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _rejectingReschedule = false);
    }
  }

  Future<void> _withdrawProposal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Retirar proposta?'),
        content: const Text(
            'O pedido ficará disponível para outros jardineiros.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Não'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Retirar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _withdrawing = true);
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(proposalRepositoryProvider)
          .withdrawProposal(widget.proposalId, _jobId);
      if (!mounted) return;
      // Regra T4: voltar (com fallback para a home quando aberto por
      // notificação) → SnackBar → invalidar.
      final jobId = _jobId;
      goBackOrToRoleHome(context);
      scaffold.showSnackBar(
          const SnackBar(content: Text('Proposta retirada.')));
      invalidateWorkerLists(ref, jobId: jobId);
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  Future<void> _openWhatsApp(String phone) =>
      openWhatsAppOrWarn(context, phone);

  Future<void> _showAddHelperSheet() async {
    int slotsNeeded = 1;
    bool equipmentRequired = false;
    bool loading = false;

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              24, 24, 24,
              24 + MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Adicionar ajudante',
                  style: Theme.of(sheetCtx).textTheme.titleMedium,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Quantos ajudantes precisas?',
                        style: Theme.of(sheetCtx).textTheme.bodyMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: slotsNeeded <= 1
                          ? null
                          : () => setSheetState(() => slotsNeeded--),
                    ),
                    Text(
                      '$slotsNeeded',
                      style: Theme.of(sheetCtx).textTheme.titleMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () => setSheetState(() => slotsNeeded++),
                    ),
                  ],
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Exigir equipamento próprio'),
                  value: equipmentRequired,
                  onChanged: loading
                      ? null
                      : (v) =>
                          setSheetState(() => equipmentRequired = v ?? false),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: loading
                      ? null
                      : () async {
                          setSheetState(() => loading = true);
                          final scaffold = ScaffoldMessenger.of(context);
                          try {
                            await ref
                                .read(helpRequestRepositoryProvider)
                                .createHelpRequest(
                                  jobId: _jobId,
                                  proposalId: widget.proposalId,
                                  slotsNeeded: slotsNeeded,
                                  equipmentRequired: equipmentRequired,
                                  createdPostConfirmation: true,
                                );
                            // Regra T4: fechar a sheet → SnackBar → invalidar.
                            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                            scaffold.showSnackBar(const SnackBar(
                              content: Text(
                                  'Pedido de ajuda enviado para aprovação do cliente.'),
                            ));
                            if (mounted) {
                              ref.invalidate(
                                  helpRequestsForJobProvider(_jobId));
                            }
                          } catch (e) {
                            scaffold.showSnackBar(SnackBar(
                              content: Text(friendlyError(e)),
                              backgroundColor: Colors.red,
                            ));
                            setSheetState(() => loading = false);
                          }
                        },
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Enviar pedido'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  /// AlertDialog de confirmação → RPC mark_job_done. Devolve true só depois
  /// da RPC confirmar sucesso — a view (AppSuccessFeedback) só aparece
  /// depois disso, e a navegação/invalidação fica em
  /// [_onCompletionFeedbackFinished], chamado pela view depois do feedback.
  Future<bool> _markCompleted() async {
    final scaffold = ScaffoldMessenger.of(context);
    final result = await MarkCompletedSheet.show(context);
    if (result == null || !mounted) return false;

    try {
      String? photoPath;
      final photo = result.photo;
      if (photo != null) {
        photoPath = await ref
            .read(jobRepositoryProvider)
            .uploadCompletionPhoto(jobId: _jobId, file: photo);
      }
      await ref
          .read(proposalRepositoryProvider)
          .markJobCompleted(_jobId, photoPath: photoPath);
      return true;
    } catch (e) {
      if (mounted) {
        scaffold.showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
      return false;
    }
  }

  void _onCompletionFeedbackFinished() {
    if (!mounted) return;
    final jobId = _jobId;
    GoRouter.of(context).go('/worker/home');
    invalidateWorkerLists(ref, jobId: jobId);
  }

  void _openTeam() {
    context.push(
      '/worker/job/$_jobId/help-requests',
      extra: const {'fromMyJob': true},
    );
  }

  Widget _notFound(String message) {
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
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }

  /// Cartão "Equipa": `null` enquanto os pedidos de ajuda carregam (nem
  /// cartão nem botão, para não deixar criar um segundo pedido por engano).
  ({bool loaded, HelpTeamSummary? summary}) _helpTeam() {
    final helpRequestsAsync = ref.watch(helpRequestsForJobProvider(_jobId));
    if (helpRequestsAsync.isLoading && !helpRequestsAsync.hasValue) {
      return (loaded: false, summary: null);
    }
    final helpRequests = helpRequestsAsync.asData?.value ?? const [];
    final candidates = <String, List<HelpAcceptance>?>{};
    for (final hr in helpRequests) {
      if (hr.status == HelpRequestStatus.cancelled ||
          hr.status == HelpRequestStatus.pendingApproval) {
        continue;
      }
      candidates[hr.id] =
          ref.watch(candidatesForHelpRequestProvider(hr.id)).asData?.value;
    }
    return (loaded: true, summary: helpTeamSummary(helpRequests, candidates));
  }

  @override
  Widget build(BuildContext context) {
    final proposalAsync = ref.watch(proposalByIdProvider(widget.proposalId));
    // Com o id na rota, o pedido carrega em paralelo com a proposta.
    if (widget.jobId.isNotEmpty) ref.watch(jobByIdProvider(widget.jobId));

    if (proposalAsync.isLoading) {
      return const Scaffold(body: AppScreenLoadingSkeleton());
    }
    if (proposalAsync.hasError) {
      return _notFound(friendlyError(proposalAsync.error!));
    }
    final proposal = proposalAsync.value;
    if (proposal == null) return _notFound('Trabalho não encontrado.');
    if (widget.jobId.isEmpty) _resolvedJobId = proposal.jobId;
    if (_jobId.isEmpty) return _notFound('Trabalho não encontrado.');

    final jobAsync = ref.watch(jobByIdProvider(_jobId));
    if (jobAsync.isLoading) {
      return const Scaffold(body: AppScreenLoadingSkeleton());
    }
    if (jobAsync.hasError) return _notFound(friendlyError(jobAsync.error!));
    final job = jobAsync.value;
    if (job == null) return _notFound('Trabalho não encontrado.');

    final currentUserId = ref.watch(currentUserIdProvider);
    final serviceTypesAsync = ref.watch(serviceTypesProvider);
    final photosAsync = ref.watch(jobPhotosProvider(_jobId));
    final clientInfoAsync = ref.watch(clientBasicInfoProvider(job.clientId));
    final helpersForRatingAsync =
        ref.watch(acceptedHelpersForJobProvider(_jobId));

    final isConfirmed = proposal.status == ProposalStatus.accepted &&
        job.status == JobStatus.confirmed;
    final ({bool loaded, HelpTeamSummary? summary}) team =
        isConfirmed ? _helpTeam() : (loaded: false, summary: null);

    final serviceType = serviceTypesAsync.value
        ?.where((s) => s.id == job.serviceTypeId)
        .firstOrNull;

    final estimate = _formatEstimate(
      proposal.hourlyRate,
      proposal.estimatedHoursMin,
      proposal.estimatedHoursMax,
    );

    final clientInfo = clientInfoAsync.asData?.value;
    final photos = photosAsync.asData?.value ?? const <String>[];
    final avatarUrl = clientInfo?['avatar_url'];

    // Só a partir do dia do trabalho (a RPC também valida, migration 0046).
    // Sem data confirmada (horário flexível) fica sempre disponível.
    final today = DateUtils.dateOnly(DateTime.now());
    final confirmedDay =
        job.confirmedDate == null ? null : DateUtils.dateOnly(job.confirmedDate!);
    final canMarkCompleted =
        confirmedDay == null || !confirmedDay.isAfter(today);

    // Mesma regra da BD (cancel_job/propose_reschedule): só até ao dia
    // anterior ao trabalho, contado em dias e não em horas.
    final dayActionsBlocked = !WorkerJobDayRules.canCancelOrReschedule(
      confirmedDate: job.confirmedDate,
      today: today,
    );
    final overdue = WorkerJobDayRules.isOverdue(
      confirmedDate: job.confirmedDate,
      today: today,
    );

    final isCancelled = job.status == JobStatus.cancelled ||
        job.status == JobStatus.noResponse;

    final data = view.WorkerMyJobDetailViewData(
      jobId: job.id,
      proposalStatus: proposal.status,
      jobStatus: job.status,
      statusPresentation: proposal.status.presentation,
      serviceLabel: serviceType?.name ?? '—',
      dateLabel: _formatDate(job.preferredDate),
      confirmedScheduleLabel: _confirmedScheduleLabel(job),
      // Com a proposta ainda pendente o servidor só manda a localidade
      // (migration 0043).
      addressLabel: proposal.status == ProposalStatus.accepted
          ? job.addressText
          : '${job.addressText} · morada exata depois de aceite',
      locationLat: job.locationLat,
      locationLng: job.locationLng,
      urgent: job.urgency == Urgency.urgent,
      sizeLabel: job.sizeEstimate?.label,
      description: job.description,
      photoUrls: photos,
      hourlyRateLabel: hourlyRateLabel(proposal.hourlyRate),
      estimatedHoursLabel: (proposal.estimatedHoursMin != null ||
              proposal.estimatedHoursMax != null)
          ? _hoursLabel(proposal.estimatedHoursMin, proposal.estimatedHoursMax)
          : null,
      estimatedTotalLabel: estimate,
      peopleNeeded: proposal.peopleNeeded,
      notes: proposal.notes,
      timelineSteps: buildJobTimeline(job),
      clientId: job.clientId,
      clientName: clientInfo?['full_name'] ?? '',
      clientAvatarUrl:
          (avatarUrl != null && avatarUrl.isNotEmpty) ? avatarUrl : null,
      clientPhone: clientInfo?['phone'] ?? '',
      rescheduleStatus: job.rescheduleStatus,
      rescheduleProposedByMe: job.rescheduleProposedBy == currentUserId,
      proposedRescheduleLabel: _proposedRescheduleLabel(job),
      cancelBlockedBy24h: dayActionsBlocked,
      rescheduleBlocked: dayActionsBlocked,
      helpersForRating: helpersForRatingAsync.asData?.value ?? const [],
      agreedPriceLabel: agreedPriceLabel(
        proposal.hourlyRate,
        proposal.estimatedHoursMin,
        proposal.estimatedHoursMax,
      ),
      canMarkCompleted: canMarkCompleted,
      markCompletedHint: confirmedDay == null
          ? null
          : 'Disponível a partir de ${DateFormat('dd/MM').format(confirmedDay)}, o dia do trabalho.',
      overdueMessage: (overdue && job.confirmedDate != null)
          ? WorkerJobDayRules.overdueMessage(job.confirmedDate!)
          : null,
      cancelledMessage: isCancelled && proposal.status == ProposalStatus.accepted
          ? (job.status == JobStatus.noResponse
              ? 'Este pedido expirou.'
              : cancelledJobBannerMessage(
                  cancelReason: job.cancelReason,
                  cancelledByMe: job.cancelledBy != null &&
                      job.cancelledBy == currentUserId,
                ))
          : null,
      helpTeamLoaded: team.loaded,
      helpTeamLabel: team.summary?.label,
      helpTeamAwaitingApproval: team.summary?.awaitingApproval ?? false,
      titleSubtitle: jobDistinguisherLabel(job),
      proposingReschedule: _proposingReschedule,
      acceptingReschedule: _acceptingReschedule,
      rejectingReschedule: _rejectingReschedule,
      cancellingJob: _cancellingJob,
      withdrawing: _withdrawing,
    );

    return view.WorkerMyJobDetailScreen(
      data: data,
      onBack: () => goBackOrToRoleHome(context),
      onCallClientPressed: () => _openWhatsApp(data.clientPhone),
      onRequestHelpersPressed: _showAddHelperSheet,
      onViewTeamPressed: _openTeam,
      onMarkCompleted: _markCompleted,
      onCompletionFeedbackFinished: _onCompletionFeedbackFinished,
      onProposeReschedule: _proposeReschedule,
      onAcceptReschedule: _acceptReschedule,
      onRejectReschedule: _rejectReschedule,
      onCancelJob: _cancelJob,
      onWithdrawProposal: _withdrawProposal,
      onPhotoTap: (index) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoViewerScreen(
            photoUrls: photos,
            initialIndex: index,
          ),
        ),
      ),
    );
  }
}

// ── helpers ──────────────────────────────────────────────────────────────────

String _proposedRescheduleLabel(JobRequest job) {
  if (job.rescheduleProposedDate == null) return '';
  final date = DateFormat('dd/MM/yyyy').format(job.rescheduleProposedDate!);
  if (job.rescheduleProposedFlexible == true) return '$date (horário flexível)';
  if (job.rescheduleProposedTime != null) {
    return '$date às ${job.rescheduleProposedTime}';
  }
  return date;
}

String _confirmedScheduleLabel(JobRequest job) {
  if (job.confirmedDate == null) return 'Data a combinar';
  final date = DateFormat('dd/MM/yyyy').format(job.confirmedDate!);
  if (job.confirmedFlexible) return '$date (horário flexível)';
  if (job.confirmedTime != null) return '$date às ${job.confirmedTime}';
  return date;
}

String _formatDate(DateTime? date) {
  if (date == null) return 'Flexível';
  return DateFormat('dd/MM/yyyy').format(date);
}

String _formatEstimate(double rate, double? min, double? max) =>
    estimatedTotalLabel(rate, min, max);

String _hoursLabel(double? min, double? max) => estimatedHoursLabel(min, max);
