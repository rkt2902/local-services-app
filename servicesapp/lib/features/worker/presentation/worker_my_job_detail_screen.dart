import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/theme/app_status_presentation.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/constants/enums.dart';
import '../../../core/router/app_back_navigation.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/price_labels.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/photo_viewer_screen.dart';
import '../../agenda/application/agenda_conflicts.dart';
import '../../agenda/application/agenda_providers.dart';
import '../../agenda/data/agenda_entry_model.dart';
import '../../agenda/presentation/agenda_day_presenter.dart';
import '../../agenda/presentation/agenda_day_preview.dart';
import '../../agenda/presentation/agenda_day_preview_view_data.dart';
import '../../agenda/presentation/agenda_slot_check.dart';
import '../../auth/application/auth_providers.dart';
import '../../jobs/application/job_labels.dart';
import '../../jobs/application/job_timeline.dart';
import '../../client/application/client_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/cancel_reasons.dart';
import '../../jobs/data/job_model.dart';
import '../../jobs/presentation/widgets/cancel_job_dialog.dart';
import '../../jobs/presentation/widgets/reschedule_dialog.dart';
import '../../help_requests/application/help_request_providers.dart';
import '../../help_requests/data/help_request_model.dart';
import '../application/worker_job_rules.dart';
import '../application/worker_list_invalidation.dart';
import '../../proposals/application/proposal_price_labels.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';
import '../../ratings/application/rating_providers.dart';
import 'widgets/mark_completed_sheet.dart';
import 'widgets/report_problem_dialog.dart';
import 'widgets/start_job_sheet.dart';
import 'widgets/worker_my_job_detail_view.dart' as view;
import '../../../core/widgets/app_toast.dart';

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
    final toast = AppToast.of(context);
    final router = GoRouter.of(context);
    try {
      final newJobId = await ref.read(jobRepositoryProvider).cancelJob(
            jobId: _jobId,
            reason: result['reason']!,
            reasonDetail: result['reasonDetail'],
          );
      // Regra T4: navegar → SnackBar → invalidar.
      router.go('/worker/home');
      toast.show(newJobId != null
            ? 'Pedido cancelado. O cliente foi notificado e o pedido foi reaberto.'
            : 'Pedido cancelado.');
      invalidateWorkerLists(ref, jobId: _jobId);
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      if (mounted) setState(() => _cancellingJob = false);
    }
  }

  /// A Agenda no diálogo de remarcar (A10, M3): "Era: …", a nota e a
  /// confirmação "Pedir mesmo assim". O próprio trabalho não conta.
  RescheduleAgenda _rescheduleAgenda() {
    final job = ref.read(jobByIdProvider(_jobId)).asData?.value;
    final now = DateTime.now();
    final date = job?.confirmedDate;
    final time = job == null || job.confirmedFlexible
        ? null
        : parseTimeMinutes(job.confirmedTime);
    final previous = date == null
        ? 'Era: sem data marcada'
        : 'Era: ${agendaWeekdayName(date).toLowerCase()}, '
              '${agendaShortDate(date, now: now)}'
              '${time == null ? '' : ' · ${formatMinutes(time)}'}';
    AgendaSlot slot(DateTime day, int? start) =>
        AgendaSlot(date: day, startMinutes: start, ignoreSourceId: _jobId);
    return RescheduleAgenda(
      previousLabel: previous,
      check: (day, start) async {
        final entries = await ref.read(
          agendaRangeProvider(agendaMonthRange(day)).future,
        );
        final serviceTypes =
            ref.read(serviceTypesProvider).asData?.value ?? const [];
        return checkAgendaSlot(
          slot: slot(day, start),
          entries: entries,
          serviceTypes: serviceTypes,
          now: DateTime.now(),
          continueLabel: 'Pedir mesmo assim',
        );
      },
      onViewDay: (day, start) => showAgendaDayPreview(
        context,
        day: day,
        ghost: AgendaDayPreviewGhost(
          date: day,
          label: 'A nova hora',
          startMinutes: start,
          slotKind: AgendaEntryKind.appJob,
          ignoreSourceId: _jobId,
        ),
      ),
    );
  }

  Future<void> _proposeReschedule() async {
    final result = await RescheduleDialog.show(
      context,
      agenda: _rescheduleAgenda(),
    );
    if (result == null || !mounted) return;

    setState(() => _proposingReschedule = true);
    final toast = AppToast.of(context);
    try {
      await ref.read(jobRepositoryProvider).proposeReschedule(
            jobId: _jobId,
            newDate: result['date'] as DateTime,
            newTime: result['time'] as String?,
            newFlexible: result['flexible'] as bool,
          );
      // Fica neste ecrã (sem pop: aberto por notificação não há nada para
      // fazer pop). SnackBar → invalidar.
      toast.show('Remarcação enviada.');
      invalidateWorkerLists(ref, jobId: _jobId);
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      if (mounted) setState(() => _proposingReschedule = false);
    }
  }

  Future<void> _acceptReschedule() async {
    setState(() => _acceptingReschedule = true);
    final toast = AppToast.of(context);
    try {
      await ref.read(jobRepositoryProvider).acceptReschedule(_jobId);
      toast.show('Nova data aceite.');
      invalidateWorkerLists(ref, jobId: _jobId);
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      if (mounted) setState(() => _acceptingReschedule = false);
    }
  }

  Future<void> _rejectReschedule() async {
    setState(() => _rejectingReschedule = true);
    final toast = AppToast.of(context);
    try {
      await ref.read(jobRepositoryProvider).rejectReschedule(_jobId);
      toast.show('Remarcação recusada.');
      invalidateWorkerLists(ref, jobId: _jobId);
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      if (mounted) setState(() => _rejectingReschedule = false);
    }
  }

  Future<void> _withdrawProposal() async {
    final confirmed = await AppConfirmDialog.show(
      context,
      icon: Icons.undo_rounded,
      title: 'Retirar proposta?',
      message: 'O pedido fica disponível para outros jardineiros.',
      confirmLabel: 'Retirar',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _withdrawing = true);
    final toast = AppToast.of(context);
    try {
      await ref
          .read(proposalRepositoryProvider)
          .withdrawProposal(widget.proposalId, _jobId);
      if (!mounted) return;
      // Regra T4: voltar (com fallback para a home quando aberto por
      // notificação) → SnackBar → invalidar.
      final jobId = _jobId;
      goBackOrToRoleHome(context);
      toast.show('Proposta retirada.');
      invalidateWorkerLists(ref, jobId: jobId);
    } catch (e) {
      toast.error(friendlyError(e));
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

    await AppSheet.show<void>(
      context,
      builder: (_) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final textTheme = Theme.of(sheetCtx).textTheme;
          Future<void> submit() async {
            setSheetState(() => loading = true);
            final toast = AppToast.of(context);
            try {
              await ref.read(helpRequestRepositoryProvider).createHelpRequest(
                    jobId: _jobId,
                    proposalId: widget.proposalId,
                    slotsNeeded: slotsNeeded,
                    equipmentRequired: equipmentRequired,
                    createdPostConfirmation: true,
                  );
              // Regra T4: fechar a sheet → aviso → invalidar.
              if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
              toast.show('Pedido de ajuda enviado para aprovação do cliente.');
              if (mounted) {
                ref.invalidate(helpRequestsForJobProvider(_jobId));
              }
            } catch (e) {
              toast.error(friendlyError(e));
              setSheetState(() => loading = false);
            }
          }

          return AppSheet(
            title: 'Adicionar ajudante',
            onClose: () => Navigator.of(sheetCtx).pop(),
            primaryActionLabel: 'Enviar pedido',
            onPrimaryAction: submit,
            isSubmitting: loading,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Quantos ajudantes precisas?',
                        style: textTheme.bodyMedium
                            ?.copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Menos um ajudante',
                      icon: const Icon(Icons.remove),
                      onPressed: slotsNeeded <= 1 || loading
                          ? null
                          : () => setSheetState(() => slotsNeeded--),
                    ),
                    Text('$slotsNeeded', style: textTheme.titleMedium),
                    IconButton(
                      tooltip: 'Mais um ajudante',
                      icon: const Icon(Icons.add),
                      onPressed: loading
                          ? null
                          : () => setSheetState(() => slotsNeeded++),
                    ),
                  ],
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Exigir equipamento próprio',
                    style: textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textPrimary),
                  ),
                  value: equipmentRequired,
                  onChanged: loading
                      ? null
                      : (v) =>
                          setSheetState(() => equipmentRequired = v ?? false),
                ),
                Text(
                  'O pedido segue para o cliente aprovar.',
                  style: textTheme.labelMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Folha "Iniciar o trabalho agora?" → upload das fotos de antes →
  /// `start_job` (migration 0052). Fica no ecrã: o provider do pedido é
  /// invalidado e o ecrã passa a "Em curso".
  Future<void> _startJob(String clientName) async {
    final toast = AppToast.of(context);
    final started = await StartJobSheet.show(
      context,
      clientName: clientName,
      onStart: (photos) async {
        try {
          final repo = ref.read(jobRepositoryProvider);
          final paths = <String>[];
          for (final photo in photos) {
            paths.add(await repo.uploadWorkPhoto(
                jobId: _jobId, file: photo, before: true));
          }
          await repo.startJob(_jobId, photoPaths: paths);
          return true;
        } catch (e) {
          toast.error(friendlyError(e));
          return false;
        }
      },
    );
    if (!started || !mounted) return;
    // Regra T4: sem navegação aqui (fica no ecrã); SnackBar → invalidar.
    toast.show('Trabalho iniciado. O cliente foi avisado.');
    invalidateWorkerLists(ref, jobId: _jobId);
  }

  /// "Terminar o dia N" (`finish_work_day`, migration 0058). Fica no ecrã.
  Future<void> _finishDay(int day) async {
    final toast = AppToast.of(context);
    try {
      await ref.read(proposalRepositoryProvider).finishWorkDay(_jobId);
    } catch (e) {
      toast.error(friendlyError(e));
      return;
    }
    if (!mounted) return;
    // Regra T4: sem navegação; aviso → invalidar.
    toast.show('Dia $day terminado. Até amanhã!');
    ref.invalidate(jobWorkDaysProvider(_jobId));
  }

  /// "Começar o dia N+1" (`start_work_day`).
  Future<void> _startNextDay(int day) async {
    final toast = AppToast.of(context);
    try {
      await ref.read(proposalRepositoryProvider).startWorkDay(_jobId);
    } catch (e) {
      toast.error(friendlyError(e));
      return;
    }
    if (!mounted) return;
    toast.show('Dia $day começado.');
    ref.invalidate(jobWorkDaysProvider(_jobId));
  }

  /// Lista e estado dos dias para o ecrã (design A6, E). `null` quando o
  /// trabalho é de um dia só ou os dias ainda não carregaram.
  view.WorkerWorkDaysViewData? _workDaysViewData(
    JobProposal proposal,
    List<JobWorkDay> days,
    DateTime now,
  ) {
    if (days.isEmpty || !isMultiDayWork(proposal, dayCount: days.length)) {
      return null;
    }
    final current = days.last;
    final planned = plannedWorkDays(proposal);
    String hm(DateTime d) => DateFormat('HH:mm').format(d.toLocal());
    final rows = <view.WorkerWorkDayRowViewData>[
      for (final d in days)
        view.WorkerWorkDayRowViewData(
          label: 'Dia ${d.dayNumber}',
          detail: d.isOpen
              ? 'Desde as ${hm(d.startedAt)} · a decorrer'
              : '${hm(d.startedAt)} a ${hm(d.endedAt!)} · ${workedTimeLabel(d.endedAt!.difference(d.startedAt))}',
          current: d.isOpen,
        ),
      if (planned != null)
        for (var n = current.dayNumber + 1; n <= planned; n++)
          view.WorkerWorkDayRowViewData(
            label: 'Dia $n',
            detail: 'Previsto',
            planned: true,
          ),
    ];
    return view.WorkerWorkDaysViewData(
      headerLabel: workDayHeaderLabel(current.dayNumber, planned),
      dayNumber: current.dayNumber,
      dayOpen: current.isOpen,
      dayStartedAt: current.isOpen ? current.startedAt : null,
      rows: rows,
      workedTotalLabel: workedTimeLabel(workedDuration(days, now: now)),
    );
  }

  /// Folha "Terminou o trabalho?" → upload das fotos de depois → RPC
  /// mark_job_done. Devolve true só depois da RPC confirmar sucesso: a view
  /// mostra o AppSuccessFeedback e a navegação/invalidação fica em
  /// [_onCompletionFeedbackFinished].
  Future<bool> _markCompleted({
    required String clientName,
    required DateTime? startedAt,
    required String priceLabel,
    required List<JobWorkDay> workDays,
    required bool multiDay,
    required bool fixedValue,
  }) async {
    final toast = AppToast.of(context);
    final now = DateTime.now();
    // Com dias registados (0058) o tempo é a soma dos dias; sem eles fica o
    // cálculo antigo desde o início.
    final worked = workDays.isNotEmpty
        ? workedTimeLabel(workedDuration(workDays, now: now))
        : startedAt == null
            ? 'Sem registo'
            : durationLabel(now.difference(startedAt));
    return MarkCompletedSheet.show(
      context,
      clientName: clientName,
      workedTimeLabel: worked,
      priceLabel: priceLabel,
      workDaysLabel:
          multiDay && workDays.isNotEmpty ? '${workDays.length}' : null,
      fixedValue: fixedValue,
      onSend: (photos) async {
        try {
          final paths = <String>[];
          for (final photo in photos) {
            paths.add(await ref.read(jobRepositoryProvider).uploadWorkPhoto(
                jobId: _jobId, file: photo, before: false));
          }
          await ref
              .read(proposalRepositoryProvider)
              .markJobCompleted(_jobId, photoPaths: paths);
          return true;
        } catch (e) {
          toast.error(friendlyError(e));
          return false;
        }
      },
    );
  }

  /// "Reportar problema" do jardineiro durante o trabalho (job_reports, a
  /// policy já deixa o jardineiro aceite reportar).
  Future<void> _reportProblem() async {
    final description = await ReportProblemDialog.show(context);
    if (description == null || !mounted) return;
    final toast = AppToast.of(context);
    try {
      await ref
          .read(proposalRepositoryProvider)
          .reportJobProblem(jobId: _jobId, description: description);
      toast.show('Relato enviado. A nossa equipa vai analisar.');
    } catch (e) {
      toast.error(friendlyError(e));
    }
  }

  void _onCompletionFeedbackFinished() {
    if (!mounted) return;
    final jobId = _jobId;
    GoRouter.of(context).go('/worker/home');
    invalidateWorkerLists(ref, jobId: jobId);
  }

  /// Fotos, tempo registado e a avaliação que o cliente deixou (design A1).
  view.WorkerCompletedJobViewData _completedViewData(
    JobRequest job,
    String clientName,
  ) {
    final repo = ref.read(jobRepositoryProvider);
    final after = job.afterPhotoPaths.isNotEmpty
        ? job.afterPhotoPaths
        : [?job.completionPhotoPath];
    final worked = job.workedDuration;
    final meta = [
      if (job.updatedAt != null)
        'Concluído a ${DateFormat('dd/MM').format(job.updatedAt!.toLocal())}.',
      if (worked != null) 'Tempo registado: ${durationLabel(worked)}.',
    ].join(' ');

    final received = ref
        .watch(myRatingsReceivedProvider)
        .asData
        ?.value
        .where((r) => r.jobId == job.id && r.partyId == job.clientId)
        .firstOrNull;
    final firstName = clientName.trim().split(RegExp(r'\s+')).first;

    return view.WorkerCompletedJobViewData(
      metaLabel: meta,
      beforePhotoUrls: job.beforePhotoPaths.map(repo.jobPhotoPublicUrl).toList(),
      afterPhotoUrls: after.map(repo.jobPhotoPublicUrl).toList(),
      receivedReview: received == null
          ? null
          : view.WorkerReceivedReviewViewData(
              authorFirstName: firstName.isNotEmpty ? firstName : 'O cliente',
              stars: received.stars,
              comment: received.comment,
            ),
    );
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
    // Dias de trabalho só depois de iniciado (migration 0058).
    final workDays = (isConfirmed && job.startedAt != null)
        ? ref.watch(jobWorkDaysProvider(_jobId)).asData?.value ??
            const <JobWorkDay>[]
        : const <JobWorkDay>[];
    final includeOptions = proposal.isFixedTotal
        ? ref.watch(proposalIncludeOptionsProvider).asData?.value ??
            const <ProposalIncludeOption>[]
        : const <ProposalIncludeOption>[];
    final ({bool loaded, HelpTeamSummary? summary}) team =
        isConfirmed ? _helpTeam() : (loaded: false, summary: null);

    final serviceType = serviceTypesAsync.value
        ?.where((s) => s.id == job.serviceTypeId)
        .firstOrNull;

    final estimate = estimatedTotalLabel(
      proposal.hourlyRate,
      proposal.estimatedHoursMin,
      proposal.estimatedHoursMax,
      peopleNeeded: proposal.peopleNeeded,
      helpersEquipmentRequired: proposal.helpersEquipmentRequired,
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

    final now = DateTime.now();
    final canStart = WorkerJobDayRules.canStart(
      confirmedDate: job.confirmedDate,
      confirmedTime: job.confirmedTime,
      confirmedFlexible: job.confirmedFlexible,
      now: now,
    );
    final startOpensAt = WorkerJobDayRules.startOpensAt(
      confirmedDate: job.confirmedDate,
      confirmedTime: job.confirmedTime,
      confirmedFlexible: job.confirmedFlexible,
    );
    final startHint =
        startJobHint(canStart: canStart, opensAt: startOpensAt, now: now);

    final accepted = proposal.status == ProposalStatus.accepted;
    final isCancelled = job.status == JobStatus.cancelled ||
        job.status == JobStatus.noResponse;
    final isExpired = job.status == JobStatus.noResponse ||
        job.cancelReason == CancelReason.expired;

    // Badge do design A1: "Agendado" e, depois de iniciado, "Em curso";
    // aceite e fora de `confirmed`, o estado do trabalho ("Cancelado",
    // "Concluído", "Expirado").
    final AppStatusPresentation statusPresentation;
    if (isConfirmed) {
      statusPresentation = job.startedAt != null
          ? const AppStatusPresentation(
              label: 'Em curso', color: AppStatusColor.info)
          : const AppStatusPresentation(
              label: 'Agendado', color: AppStatusColor.success);
    } else if (accepted && isCancelled && isExpired) {
      statusPresentation = const AppStatusPresentation(
          label: 'Expirado', color: AppStatusColor.neutral);
    } else if (accepted) {
      statusPresentation = job.status.presentation();
    } else {
      statusPresentation = proposal.status.presentation;
    }

    final clientName = clientInfo?['full_name'] ?? '';
    final area = jobAreaLabel(job);

    final inactive = accepted && isCancelled
        ? () {
            final message = inactiveJobMessage(
              cancelReason: job.cancelReason,
              cancelledByMe:
                  job.cancelledBy != null && job.cancelledBy == currentUserId,
              noResponse: job.status == JobStatus.noResponse,
              endedAt: job.updatedAt,
            );
            return view.WorkerInactiveJobViewData(
              title: message.title,
              body: message.body,
              expired: message.expired,
              areaLabel: area,
            );
          }()
        : null;

    final completed = accepted && job.status == JobStatus.completed
        ? _completedViewData(job, clientName)
        : null;

    final data = view.WorkerMyJobDetailViewData(
      jobId: job.id,
      proposalStatus: proposal.status,
      jobStatus: job.status,
      statusPresentation: statusPresentation,
      serviceLabel: serviceType?.name ?? '—',
      dateLabel: _formatDate(job.preferredDate),
      confirmedScheduleLabel: workerScheduleLabel(
        date: job.confirmedDate,
        time: job.confirmedTime,
        flexible: job.confirmedFlexible,
        now: now,
      ),
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
      hourlyRateLabel: proposal.isFixedTotal
          ? proposalValueLabel(proposal)
          : hourlyRateLabel(proposal.hourlyRate),
      priceRowLabel: proposal.isFixedTotal ? 'Valor total' : 'Taxa/hora',
      durationRowLabel:
          proposal.isFixedTotal ? 'Duração' : 'Horas estimadas',
      estimatedHoursLabel: proposal.estimatedDaysMin != null ||
              proposal.estimatedDaysMax != null
          ? proposalDurationLabel(proposal)
          : (proposal.estimatedHoursMin != null ||
                  proposal.estimatedHoursMax != null)
              ? _hoursLabel(
                  proposal.estimatedHoursMin, proposal.estimatedHoursMax)
              : null,
      estimatedTotalLabel: proposal.isFixedTotal ? '' : estimate,
      peopleNeeded: proposal.peopleNeeded,
      notes: proposal.notes,
      timelineSteps: buildJobTimeline(job, now: now),
      clientId: job.clientId,
      clientName: clientName,
      clientAvatarUrl:
          (avatarUrl != null && avatarUrl.isNotEmpty) ? avatarUrl : null,
      clientPhone: clientInfo?['phone'] ?? '',
      rescheduleStatus: job.rescheduleStatus,
      rescheduleProposedByMe: job.rescheduleProposedBy == currentUserId,
      proposedRescheduleLabel: _proposedRescheduleLabel(job),
      cancelBlockedBy24h: dayActionsBlocked,
      rescheduleBlocked: dayActionsBlocked,
      helpersForRating: helpersForRatingAsync.asData?.value ?? const [],
      agreedPriceLabel: acceptedProposalPriceLabel(proposal),
      canMarkCompleted: canMarkCompleted,
      startedAt: job.startedAt,
      workDays: _workDaysViewData(proposal, workDays, now),
      fixedValue: proposal.isFixedTotal
          ? view.WorkerFixedValueViewData(
              valueLabel: compactMoneyLabel(proposal.totalPrice!),
              includesLabel: _includesLabel(proposal, includeOptions),
            )
          : null,
      canStart: canStart,
      startHint: startHint,
      markCompletedHint: confirmedDay == null
          ? null
          : 'Disponível a partir de ${DateFormat('dd/MM').format(confirmedDay)}, o dia do trabalho.',
      overdueMessage: (overdue && job.confirmedDate != null)
          ? WorkerJobDayRules.overdueMessage(job.confirmedDate!)
          : null,
      inactive: inactive,
      completed: completed,
      helpTeamLoaded: team.loaded,
      // Mesma regra da BD (0054): pedir ajudantes só até à véspera.
      canRequestHelpers: confirmedDay == null || confirmedDay.isAfter(today),
      helpTeam: _teamViewData(
        team.summary,
        helpersForRatingAsync.asData?.value ?? const [],
      ),
      // Aceite: "Sofia Marques · Cascais" (design A1); antes disso o nome
      // do cliente pode não estar acessível (RLS), fica zona e data.
      titleSubtitle: accepted
          ? '${clientName.isNotEmpty ? clientName : 'Cliente'} · $area'
          : jobDistinguisherLabel(job),
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
      onMarkCompleted: () => _markCompleted(
        clientName: data.clientName,
        startedAt: job.startedAt,
        priceLabel: proposal.isFixedTotal
            ? compactMoneyLabel(proposal.totalPrice!)
            : data.agreedPriceLabel,
        workDays: workDays,
        multiDay: data.workDays != null,
        fixedValue: proposal.isFixedTotal,
      ),
      onFinishDay: data.workDays == null
          ? null
          : () => _finishDay(data.workDays!.dayNumber),
      onStartNextDay: data.workDays == null
          ? null
          : () => _startNextDay(data.workDays!.dayNumber + 1),
      onStartJob: () => _startJob(data.clientName),
      onReportProblem: _reportProblem,
      onCompletionFeedbackFinished: _onCompletionFeedbackFinished,
      onProposeReschedule: _proposeReschedule,
      onAcceptReschedule: _acceptReschedule,
      onRejectReschedule: _rejectReschedule,
      onCancelJob: _cancelJob,
      onWithdrawProposal: _withdrawProposal,
      onWorkPhotoTap: (urls, index) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoViewerScreen(
            photoUrls: urls,
            initialIndex: index,
          ),
        ),
      ),
      onBrowseAvailableJobs: () => context.go('/worker/available-jobs'),
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

String _formatDate(DateTime? date) {
  if (date == null) return 'Flexível';
  return DateFormat('dd/MM/yyyy').format(date);
}

String _hoursLabel(double? min, double? max) => estimatedHoursLabel(min, max);

/// Cartão "Equipa" a partir do resumo dos pedidos de ajuda e dos ajudantes
/// aceites (que dão as iniciais). `null` = sem pedido de ajudantes ativo.
view.WorkerJobTeamViewData? _teamViewData(
  HelpTeamSummary? summary,
  List<AcceptedHelper> helpers,
) {
  if (summary == null) return null;
  if (summary.awaitingApproval) {
    return const view.WorkerJobTeamViewData(
      memberNames: [],
      emptySlots: 0,
      pendingLabel: 'À espera de aprovação do cliente',
      awaitingApproval: true,
    );
  }
  final filled = summary.filled;
  final members = helpers.take(summary.slots).toList();
  final names = members.map((h) => h.fullName).toList();
  final avatars = members.map((h) => h.avatarUrl).toList();
  // Nomes ainda a carregar: círculos com "?" em vez de vagas vazias.
  while (filled != null && names.length < filled) {
    names.add('');
  }
  final undecided = summary.undecided ?? 0;
  return view.WorkerJobTeamViewData(
    memberNames: names,
    memberAvatarUrls: avatars,
    emptySlots: (summary.slots - (filled ?? names.length)).clamp(0, summary.slots),
    filledLabel: filled == null
        ? null
        : '$filled de ${summary.slots} ${summary.slots == 1 ? 'vaga' : 'vagas'}',
    pendingLabel: undecided > 0
        ? '$undecided ${undecided == 1 ? 'candidato' : 'candidatos'} por decidir'
        : null,
  );
}

/// "Inclui material, remoção de resíduos". `null` sem nada incluído.
String? _includesLabel(JobProposal p, List<ProposalIncludeOption> options) {
  final summary = proposalIncludesSummaryLabel(p, options);
  if (summary == null) return null;
  return 'Inclui ${summary[0].toLowerCase()}${summary.substring(1)}';
}
