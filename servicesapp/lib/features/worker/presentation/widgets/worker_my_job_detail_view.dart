import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/enums.dart';
import '../../../../core/models/job_flow_stage.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/theme/app_status_presentation.dart';
import '../../../../core/widgets/address_map_link.dart';
import '../../../../core/widgets/app_whatsapp_button.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_status_badge.dart';
import '../../../../core/widgets/app_tab_header.dart';
import '../../../../core/widgets/job_flow_stepper.dart';
import '../../../../core/widgets/primary_action_button.dart';
import '../../../../core/widgets/status_timeline.dart';
import '../../../../core/widgets/user_avatar_with_name.dart';
import '../../../ratings/application/rating_providers.dart';
import '../../application/worker_job_rules.dart';
import '../../../ratings/presentation/submit_rating_sheet.dart';

/// Dados de apresentação do ecrã "O meu trabalho" (design A1 + estados
/// preservados de sessões anteriores).
///
/// A integração (worker_my_job_detail_screen.dart) mapeia os models reais
/// (JobProposal/JobRequest) para esta estrutura. Este ecrã não consulta
/// providers, repositories ou Supabase diretamente — a única exceção são
/// as linhas de "Avaliações" (_RatingTargetRow), ConsumerWidgets
/// auto-contidos como o antigo _PrincipalRatingCard (mesmo padrão usado
/// noutros pontos da app, ex. _RatingChip em worker_jobs_screen.dart).
class WorkerMyJobDetailViewData {
  const WorkerMyJobDetailViewData({
    required this.jobId,
    required this.proposalStatus,
    required this.jobStatus,
    required this.statusPresentation,
    required this.serviceLabel,
    required this.dateLabel,
    required this.confirmedScheduleLabel,
    required this.addressLabel,
    required this.locationLat,
    required this.locationLng,
    required this.urgent,
    required this.description,
    required this.photoUrls,
    required this.hourlyRateLabel,
    required this.estimatedTotalLabel,
    required this.peopleNeeded,
    required this.timelineSteps,
    required this.clientId,
    required this.clientName,
    required this.clientAvatarUrl,
    required this.clientPhone,
    required this.rescheduleStatus,
    required this.rescheduleProposedByMe,
    required this.proposedRescheduleLabel,
    required this.cancelBlockedBy24h,
    required this.helpersForRating,
    required this.agreedPriceLabel,
    required this.canMarkCompleted,
    this.markCompletedHint,
    this.startedAt,
    this.workDays,
    this.fixedValue,
    this.priceRowLabel = 'Taxa/hora',
    this.durationRowLabel = 'Horas estimadas',
    this.canStart = false,
    this.startHint,
    this.rescheduleBlocked = false,
    this.overdueMessage,
    this.inactive,
    this.completed,
    this.helpTeamLoaded = false,
    this.helpTeam,
    this.canRequestHelpers = true,
    this.titleSubtitle,
    this.flowStage,
    this.flowShowTeam = false,
    this.teamTabBadge,
    this.sizeLabel,
    this.estimatedHoursLabel,
    this.notes,
    this.proposingReschedule = false,
    this.acceptingReschedule = false,
    this.rejectingReschedule = false,
    this.cancellingJob = false,
    this.withdrawing = false,
  });

  final String jobId;

  final ProposalStatus proposalStatus;
  final JobStatus jobStatus;
  final AppStatusPresentation statusPresentation;

  final String serviceLabel;
  final String dateLabel;

  /// "Qui, 23/10 · 9:00".
  final String confirmedScheduleLabel;

  final String addressLabel;
  final double locationLat;
  final double locationLng;
  final bool urgent;
  final String? sizeLabel;

  final String description;
  final List<String> photoUrls;

  final String hourlyRateLabel;
  final String? estimatedHoursLabel;
  final String estimatedTotalLabel;
  final int peopleNeeded;
  final String? notes;

  final List<StatusTimelineStepData> timelineSteps;

  /// Fase do stepper do fluxo (A12). Com fase, o stepper fica no cabeçalho
  /// e substitui o timeline; `null` (proposta recusada ou retirada, pedido
  /// cancelado) mantém o timeline.
  final JobFlowStage? flowStage;

  /// Mostra a fase Equipa: só quando o trabalho tem ajudantes.
  final bool flowShowTeam;

  /// "1/2" no separador Equipa (A12); `null` sem número.
  final String? teamTabBadge;

  final String clientId;
  final String clientName;
  final String? clientAvatarUrl;
  final String clientPhone;

  final RescheduleStatus? rescheduleStatus;
  final bool rescheduleProposedByMe;
  final String proposedRescheduleLabel;

  /// Cancelar bloqueado: a BD só deixa até ao dia anterior ao trabalho.
  final bool cancelBlockedBy24h;

  /// Remarcar bloqueado pela mesma regra (propose_reschedule).
  final bool rescheduleBlocked;

  /// "A data já passou..." quando o trabalho confirmado está atrasado.
  final String? overdueMessage;

  /// Trabalho aceite que já não vai acontecer (cancelado ou expirado):
  /// cartão vermelho ou cinzento, dados esbatidos e sem ações.
  final WorkerInactiveJobViewData? inactive;

  /// Trabalho concluído: tempo registado, fotos e avaliações.
  final WorkerCompletedJobViewData? completed;

  /// `false` enquanto os pedidos de ajuda carregam: não mostra nem o cartão
  /// "Equipa" nem o botão "Preciso de ajudantes".
  final bool helpTeamLoaded;

  /// Cartão "Equipa"; `null` = sem pedido de ajudantes ativo.
  final WorkerJobTeamViewData? helpTeam;

  /// "Preciso de ajudantes" só até à véspera do trabalho (0054). No dia,
  /// sem equipa, não aparece nada.
  final bool canRequestHelpers;

  final List<AcceptedHelper> helpersForRating;

  /// Taxa e intervalo total acordados ("25,00 €/h · ≈ 50 a 100 €").
  final String agreedPriceLabel;

  /// "Marcar como concluído" só a partir do dia do trabalho (0046).
  final bool canMarkCompleted;

  /// Texto por baixo do botão quando ainda não pode concluir.
  final String? markCompletedHint;

  /// Início do trabalho (migration 0052). Preenchido = "Em curso": o botão
  /// do fundo passa a "Marcar como concluído" e aparece o temporizador.
  final DateTime? startedAt;

  /// Trabalho em vários dias (design A6, E): "Dia 1 de 3", a lista dos
  /// dias e os botões "Terminar o dia" / "Começar o dia". `null` quando o
  /// trabalho é de um dia só.
  final WorkerWorkDaysViewData? workDays;

  /// Cartão "Valor fechado" (proposta com valor total). `null` por hora.
  final WorkerFixedValueViewData? fixedValue;

  /// Etiquetas do resumo "A minha proposta": "Valor total" e "Duração"
  /// numa proposta com valor fechado.
  final String priceRowLabel;
  final String durationRowLabel;

  /// "Iniciar trabalho" disponível (a partir de 1h antes da hora).
  final bool canStart;

  /// Texto por baixo de "Iniciar trabalho".
  final String? startHint;

  /// "Sofia Marques · Cascais" por baixo do título.
  final String? titleSubtitle;

  final bool proposingReschedule;
  final bool acceptingReschedule;
  final bool rejectingReschedule;
  final bool cancellingJob;
  final bool withdrawing;
}

/// Estado do trabalho em vários dias. Os inícios e fins vêm sempre da BD
/// (`get_job_work_days`): o relógio só conta a partir de [dayStartedAt].
class WorkerWorkDaysViewData {
  const WorkerWorkDaysViewData({
    required this.headerLabel,
    required this.dayNumber,
    required this.dayOpen,
    required this.rows,
    required this.workedTotalLabel,
    this.dayStartedAt,
  });

  /// "Dia 1 de 3" ou "Dia 4 · além dos 3 previstos".
  final String headerLabel;

  /// Dia atual (o aberto, ou o último terminado).
  final int dayNumber;

  /// O dia atual está a decorrer (relógio a contar).
  final bool dayOpen;

  /// Início do dia atual, quando está aberto.
  final DateTime? dayStartedAt;

  final List<WorkerWorkDayRowViewData> rows;

  /// Soma dos dias: "17 h 40 min".
  final String workedTotalLabel;
}

/// Uma linha da lista "Dias de trabalho": "Dia 1" · "09:02 a 17:10 · 8 h 8 min".
class WorkerWorkDayRowViewData {
  const WorkerWorkDayRowViewData({
    required this.label,
    required this.detail,
    this.current = false,
    this.planned = false,
  });

  final String label;
  final String detail;

  /// Dia a decorrer.
  final bool current;

  /// Dia previsto que ainda não começou.
  final bool planned;
}

/// "Valor fechado": o total e o que inclui. Não muda com as horas.
class WorkerFixedValueViewData {
  const WorkerFixedValueViewData({
    required this.valueLabel,
    this.includesLabel,
  });

  final String valueLabel;

  /// "Inclui material, remoção de resíduos". `null` sem nada incluído.
  final String? includesLabel;
}

/// Cartão "Equipa" do design A1: "1 de 2 vagas", um círculo por vaga e o
/// número de candidatos por decidir.
class WorkerJobTeamViewData {
  const WorkerJobTeamViewData({
    required this.memberNames,
    this.memberAvatarUrls = const [],
    required this.emptySlots,
    this.filledLabel,
    this.pendingLabel,
    this.awaitingApproval = false,
  });

  /// Ajudantes já na equipa, por ordem (dão as iniciais dos círculos).
  final List<String> memberNames;

  /// Fotos pela mesma ordem de [memberNames]; sem foto, ficam as iniciais.
  final List<String?> memberAvatarUrls;

  /// Vagas ainda por preencher (círculos vazios).
  final int emptySlots;

  /// "1 de 2 vagas"; `null` enquanto os candidatos carregam.
  final String? filledLabel;

  /// "2 candidatos por decidir" ou "À espera de aprovação do cliente".
  final String? pendingLabel;
  final bool awaitingApproval;
}

class WorkerInactiveJobViewData {
  const WorkerInactiveJobViewData({
    required this.title,
    required this.body,
    required this.expired,
    required this.areaLabel,
  });

  final String title;
  final String body;

  /// Expirado: ampulheta a cinzento em vez do calendário a vermelho.
  final bool expired;

  /// Só a localidade: a morada exata já não interessa.
  final String areaLabel;
}

class WorkerCompletedJobViewData {
  const WorkerCompletedJobViewData({
    required this.metaLabel,
    this.beforePhotoUrls = const [],
    this.afterPhotoUrls = const [],
    this.receivedReview,
  });

  /// "Concluído a 23/10. Tempo registado: 2h 40min."
  final String metaLabel;
  final List<String> beforePhotoUrls;
  final List<String> afterPhotoUrls;

  /// Avaliação que o cliente deixou ao jardineiro neste trabalho.
  final WorkerReceivedReviewViewData? receivedReview;
}

class WorkerReceivedReviewViewData {
  const WorkerReceivedReviewViewData({
    required this.authorFirstName,
    required this.stars,
    this.comment,
  });

  final String authorFirstName;
  final int stars;
  final String? comment;
}

class WorkerMyJobDetailScreen extends StatefulWidget {
  const WorkerMyJobDetailScreen({
    required this.data,
    required this.onBack,
    required this.onCallClientPressed,
    required this.onRequestHelpersPressed,
    required this.onViewTeamPressed,
    required this.onMarkCompleted,
    required this.onStartJob,
    required this.onReportProblem,
    required this.onProposeReschedule,
    required this.onAcceptReschedule,
    required this.onRejectReschedule,
    required this.onCancelJob,
    required this.onWithdrawProposal,
    required this.onPhotoTap,
    required this.onWorkPhotoTap,
    required this.onBrowseAvailableJobs,
    super.key,
    this.onCompletionFeedbackFinished,
    this.onFinishDay,
    this.onStartNextDay,
    this.teamTab,
  });

  final WorkerMyJobDetailViewData data;

  final VoidCallback onBack;
  final VoidCallback onCallClientPressed;
  final VoidCallback onRequestHelpersPressed;
  final VoidCallback onViewTeamPressed;

  /// Deve devolver true apenas depois da RPC (mark_job_done) confirmar
  /// sucesso — o AlertDialog de confirmação já vive dentro deste callback,
  /// no wrapper (ver worker_my_job_detail_screen.dart _markCompleted).
  final Future<bool> Function() onMarkCompleted;

  /// Abre a folha "Iniciar o trabalho agora?" e chama `start_job`. A view
  /// só mostra o estado de carregamento; o ecrã atualiza pelo provider.
  final Future<void> Function() onStartJob;

  final VoidCallback onReportProblem;

  final VoidCallback onProposeReschedule;
  final VoidCallback onAcceptReschedule;
  final VoidCallback onRejectReschedule;
  final VoidCallback onCancelJob;
  final VoidCallback onWithdrawProposal;
  final ValueChanged<int> onPhotoTap;

  /// Abre as fotos de antes ou de depois em ecrã inteiro.
  final void Function(List<String> urls, int index) onWorkPhotoTap;

  /// "Ver pedidos disponíveis" num trabalho cancelado ou expirado.
  final VoidCallback onBrowseAvailableJobs;

  /// Executado depois do AppSuccessFeedback — navega para /worker/home.
  final VoidCallback? onCompletionFeedbackFinished;

  /// "Terminar o dia N" (`finish_work_day`). Só em trabalhos de vários dias.
  final Future<void> Function()? onFinishDay;

  /// "Começar o dia N+1" (`start_work_day`).
  final Future<void> Function()? onStartNextDay;

  /// Conteúdo do separador Equipa (A12, a equipa e os candidatos). Só
  /// aparece num trabalho marcado com ajudantes ([WorkerMyJobDetailViewData
  /// .flowShowTeam]); sem ele não há separadores.
  final Widget? teamTab;

  @override
  State<WorkerMyJobDetailScreen> createState() {
    return _WorkerMyJobDetailScreenState();
  }
}

class _WorkerMyJobDetailScreenState extends State<WorkerMyJobDetailScreen> {
  bool _completing = false;
  bool _starting = false;
  bool _changingDay = false;
  bool _showSuccessFeedback = false;
  Timer? _successTimer;

  /// Separador aberto: 0 Resumo, 1 Equipa.
  int _tab = 0;

  Future<void> _handleMarkCompleted() async {
    if (_completing) return;

    setState(() => _completing = true);

    bool completed = false;
    try {
      completed = await widget.onMarkCompleted();
    } finally {
      if (mounted) setState(() => _completing = false);
    }

    if (!mounted || !completed) return;

    setState(() => _showSuccessFeedback = true);

    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    _successTimer?.cancel();
    _successTimer = Timer(
      disableAnimations ? Duration.zero : const Duration(milliseconds: 1100),
      () {
        if (!mounted) return;
        setState(() => _showSuccessFeedback = false);
        widget.onCompletionFeedbackFinished?.call();
      },
    );
  }

  Future<void> _handleStart() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await widget.onStartJob();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _handleDayAction(Future<void> Function()? action) async {
    if (_changingDay || action == null) return;
    setState(() => _changingDay = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _changingDay = false);
    }
  }

  @override
  void dispose() {
    _successTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final accepted = data.proposalStatus == ProposalStatus.accepted;
    final isConfirmed = accepted && data.jobStatus == JobStatus.confirmed;

    final showTabs = isConfirmed && data.flowShowTeam && widget.teamTab != null;

    final Widget body;
    if (showTabs) {
      body = IndexedStack(
        index: _tab,
        children: [_buildConfirmedBody(context), widget.teamTab!],
      );
    } else if (isConfirmed) {
      body = _buildConfirmedBody(context);
    } else if (accepted && data.inactive != null) {
      body = _InactiveJobBody(
        inactive: data.inactive!,
        dateTimeLabel: data.confirmedScheduleLabel,
        priceLabel: data.agreedPriceLabel,
        clientName: data.clientName,
        clientAvatarUrl: data.clientAvatarUrl,
        onBrowseAvailableJobs: widget.onBrowseAvailableJobs,
      );
    } else if (accepted &&
        data.jobStatus == JobStatus.completed &&
        data.completed != null) {
      body = _CompletedJobBody(
        data: data,
        completed: data.completed!,
        onWorkPhotoTap: widget.onWorkPhotoTap,
      );
    } else {
      body = _buildOtherBody(context);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          onPressed: widget.onBack,
          tooltip: 'Voltar',
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
        ),
        titleSpacing: 0,
        title: AppBarTitle(
          title: data.serviceLabel,
          subtitle: data.titleSubtitle,
        ),
        actions: [
          AppBarStatusBadge.fromPresentation(
            presentation: data.statusPresentation,
          ),
        ],
        bottom: data.flowStage == null
            ? null
            : PreferredSize(
                preferredSize: Size.fromHeight(showTabs ? 44 + 48 : 44),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    JobFlowStepper(
                      stage: data.flowStage!,
                      showTeam: data.flowShowTeam,
                    ),
                    if (showTabs)
                      AppTabs(
                        items: [
                          const AppTabItem(label: 'Resumo'),
                          AppTabItem(label: 'Equipa', badge: data.teamTabBadge),
                        ],
                        selectedIndex: _tab,
                        onSelected: (i) => setState(() => _tab = i),
                      ),
                  ],
                ),
              ),
      ),
      body: Stack(
        children: [
          body,
          Positioned.fill(
            child: AppSuccessFeedback(
              visible: _showSuccessFeedback,
              message: 'Trabalho concluído',
            ),
          ),
        ],
      ),
    );
  }

  /// Com separadores, o cartão Equipa do Resumo abre o separador.
  bool get _hasTeamTab => widget.data.flowShowTeam && widget.teamTab != null;

  // ── Agendado / em curso (design A1, primeira coluna) ──────────────────────

  Widget _buildConfirmedBody(BuildContext context) {
    final data = widget.data;
    final textTheme = Theme.of(context).textTheme;
    final hasMap = !(data.locationLat == 0 && data.locationLng == 0);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (data.flowStage == null)
                  AppStaggeredEntrance(
                    index: 0,
                    child: StatusTimelineHorizontal(steps: data.timelineSteps),
                  ),
                if (data.overdueMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppStaggeredEntrance(
                    index: 0,
                    child: _InfoBanner(
                      icon: Icons.event_busy_rounded,
                      color: AppStatusColor.waiting,
                      message: data.overdueMessage!,
                    ),
                  ),
                ],
                if (data.startedAt != null && data.workDays == null) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppStaggeredEntrance(
                    index: 1,
                    child: _WorkTimerCard(
                      startedAt: data.startedAt!,
                      estimatedHoursLabel: data.estimatedHoursLabel,
                    ),
                  ),
                ],
                if (data.startedAt != null && data.workDays != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppStaggeredEntrance(
                    index: 1,
                    child:
                        data.workDays!.dayOpen &&
                            data.workDays!.dayStartedAt != null
                        ? _WorkTimerCard(
                            startedAt: data.workDays!.dayStartedAt!,
                            title: data.workDays!.headerLabel,
                          )
                        : _DayPausedCard(workDays: data.workDays!),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppStaggeredEntrance(
                    index: 1,
                    child: _WorkDaysCard(workDays: data.workDays!),
                  ),
                ],
                if (data.rescheduleStatus == RescheduleStatus.pending) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppStaggeredEntrance(
                    index: 1,
                    child: _RescheduleBanner(
                      proposedByMe: data.rescheduleProposedByMe,
                      label: data.proposedRescheduleLabel,
                      accepting: data.acceptingReschedule,
                      rejecting: data.rejectingReschedule,
                      onAccept: widget.onAcceptReschedule,
                      onReject: widget.onRejectReschedule,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                AppStaggeredEntrance(
                  index: 2,
                  child: _JobFactsCard(
                    dateTimeLabel: data.confirmedScheduleLabel,
                    locationLabel: data.addressLabel,
                    priceLabel: data.agreedPriceLabel,
                    onOpenMap: hasMap
                        ? () => AddressMapLink.openInMaps(
                            data.locationLat,
                            data.locationLng,
                          )
                        : null,
                  ),
                ),
                if (data.fixedValue != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppStaggeredEntrance(
                    index: 2,
                    child: _FixedValueCard(fixedValue: data.fixedValue!),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                AppStaggeredEntrance(
                  index: 3,
                  child: _ClientWhatsAppCard(
                    name: data.clientName,
                    avatarUrl: data.clientAvatarUrl,
                    onWhatsApp: data.clientPhone.isEmpty
                        ? null
                        : widget.onCallClientPressed,
                  ),
                ),
                if (data.helpTeamLoaded &&
                    (data.helpTeam != null || data.canRequestHelpers)) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppStaggeredEntrance(
                    index: 4,
                    child: data.helpTeam != null
                        ? _TeamCard(
                            team: data.helpTeam!,
                            onViewTeam: _hasTeamTab
                                ? () => setState(() => _tab = 1)
                                : widget.onViewTeamPressed,
                          )
                        : _HelpersActionButton(
                            onPressed: widget.onRequestHelpersPressed,
                          ),
                  ),
                ],
                if (data.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppStaggeredEntrance(
                    index: 5,
                    child: _DescriptionSection(
                      description: data.description,
                      photoUrls: data.photoUrls,
                      onPhotoTap: widget.onPhotoTap,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                AppStaggeredEntrance(
                  index: 6,
                  child: _RescheduleCancelRow(
                    reschedulePending:
                        data.rescheduleStatus == RescheduleStatus.pending,
                    proposingReschedule: data.proposingReschedule,
                    cancelling: data.cancellingJob,
                    cancelBlockedBy24h: data.cancelBlockedBy24h,
                    rescheduleBlocked: data.rescheduleBlocked,
                    onProposeReschedule: widget.onProposeReschedule,
                    onCancelJob: widget.onCancelJob,
                  ),
                ),
              ],
            ),
          ),
        ),
        _BottomBar(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (data.startedAt == null) ...[
                PrimaryActionButton(
                  label: 'Iniciar trabalho',
                  icon: data.canStart
                      ? Icons.play_arrow_rounded
                      : Icons.lock_outline_rounded,
                  isLoading: _starting,
                  onPressed: (_starting || !data.canStart)
                      ? null
                      : _handleStart,
                ),
                if (data.startHint != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    data.startHint!,
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ] else if (data.workDays != null) ...[
                PrimaryActionButton(
                  label: data.workDays!.dayOpen
                      ? 'Terminar o dia ${data.workDays!.dayNumber}'
                      : 'Começar o dia ${data.workDays!.dayNumber + 1}',
                  icon: data.workDays!.dayOpen
                      ? Icons.nightlight_outlined
                      : Icons.play_arrow_rounded,
                  isLoading: _changingDay,
                  onPressed: (_changingDay || _completing)
                      ? null
                      : () => _handleDayAction(
                          data.workDays!.dayOpen
                              ? widget.onFinishDay
                              : widget.onStartNextDay,
                        ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  height: AppSizes.buttonHeight,
                  child: OutlinedButton.icon(
                    onPressed:
                        (_completing || _changingDay || !data.canMarkCompleted)
                        ? null
                        : _handleMarkCompleted,
                    icon: _completing
                        ? const SizedBox.square(
                            dimension: AppSizes.infoRowIcon,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('Concluir trabalho'),
                  ),
                ),
                if (!data.canMarkCompleted &&
                    data.markCompletedHint != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    data.markCompletedHint!,
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                TextButton(
                  onPressed: widget.onReportProblem,
                  style: TextButton.styleFrom(
                    foregroundColor: AppStatusColor.cancelled.foreground,
                  ),
                  child: const Text(
                    'Reportar problema',
                    style: TextStyle(decoration: TextDecoration.underline),
                  ),
                ),
              ] else ...[
                PrimaryActionButton(
                  label: 'Marcar como concluído',
                  icon: Icons.check_circle_outline_rounded,
                  isLoading: _completing,
                  onPressed: (_completing || !data.canMarkCompleted)
                      ? null
                      : _handleMarkCompleted,
                ),
                if (!data.canMarkCompleted &&
                    data.markCompletedHint != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    data.markCompletedHint!,
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                TextButton(
                  onPressed: widget.onReportProblem,
                  style: TextButton.styleFrom(
                    foregroundColor: AppStatusColor.cancelled.foreground,
                  ),
                  child: const Text(
                    'Reportar problema',
                    style: TextStyle(decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Outros estados (rejected/superseded/pending, e accepted à espera de
  // confirmação) — conteúdo/lógica preservados de sessões anteriores, só com
  // limpeza de tokens (AppColors/AppSpacing/AppRadius) para consistência
  // visual com o resto da app.

  Widget _buildOtherBody(BuildContext context) {
    final data = widget.data;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data.flowStage == null) ...[
              AppStaggeredEntrance(
                index: 0,
                child: StatusTimelineCard(steps: data.timelineSteps),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            AppStaggeredEntrance(index: 1, child: _JobSummaryCard(data: data)),
            const SizedBox(height: AppSpacing.md),
            AppStaggeredEntrance(
              index: 2,
              child: Text(
                'Descrição',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            AppStaggeredEntrance(
              index: 2,
              child: _DescriptionSection(
                description: data.description,
                photoUrls: data.photoUrls,
                onPhotoTap: widget.onPhotoTap,
                showTitle: false,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppStaggeredEntrance(
              index: 3,
              child: _ProposalSummaryCard(data: data),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppStaggeredEntrance(index: 4, child: _branchBody(context)),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _branchBody(BuildContext context) {
    final data = widget.data;
    final textTheme = Theme.of(context).textTheme;

    if (data.proposalStatus == ProposalStatus.accepted) {
      // confirmed, completed, cancelled e noResponse têm composição própria
      // (design A1); aqui só chega awaitingConfirmation.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.rescheduleStatus == RescheduleStatus.pending) ...[
            _RescheduleBanner(
              proposedByMe: data.rescheduleProposedByMe,
              label: data.proposedRescheduleLabel,
              accepting: data.acceptingReschedule,
              rejecting: data.rejectingReschedule,
              onAccept: widget.onAcceptReschedule,
              onReject: widget.onRejectReschedule,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Text(
            'Cliente',
            style: textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ClientContactCard(
            name: data.clientName,
            avatarUrl: data.clientAvatarUrl,
            phone: data.clientPhone,
            onCallPressed: widget.onCallClientPressed,
          ),
          const SizedBox(height: AppSpacing.md),
          const _InfoBanner(
            icon: Icons.hourglass_top_rounded,
            color: AppStatusColor.info,
            message: WorkerJobDayRules.awaitingConfirmationMessage,
          ),
        ],
      );
    }

    if (data.proposalStatus == ProposalStatus.rejected) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _InfoBanner(
            icon: Icons.info_outline_rounded,
            color: AppStatusColor.cancelled,
            message:
                'A tua proposta não foi selecionada. O cliente escolheu outra proposta.',
          ),
          if (data.clientPhone.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: widget.onCallClientPressed,
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Contactar cliente para novo pedido'),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Podes contactar o cliente para negociar e enviar uma nova proposta.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      );
    }

    if (data.proposalStatus == ProposalStatus.superseded) {
      return const _InfoBanner(
        icon: Icons.undo_rounded,
        color: AppStatusColor.neutral,
        message: 'Retiraste a tua proposta para este pedido.',
      );
    }

    // pending
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _InfoBanner(
          icon: Icons.schedule_outlined,
          color: AppStatusColor.waiting,
          message: 'A tua proposta está à espera de resposta do cliente.',
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: data.withdrawing ? null : widget.onWithdrawProposal,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppStatusColor.cancelled.foreground,
            side: BorderSide(color: AppStatusColor.cancelled.foreground),
          ),
          child: data.withdrawing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Retirar proposta'),
        ),
      ],
    );
  }
}

// ── Blocos do design A1 ────────────────────────────────────────────────────

/// "Sofia Marques" → "SM"; um só nome → "S".
String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  final first = parts.first[0];
  final last = parts.length > 1 ? parts.last[0] : '';
  return '$first$last'.toUpperCase();
}

/// Barra branca do fundo com a ação principal do estado.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({
    required this.name,
    this.avatarUrl,
    this.size = AppSizes.avatarSmall,
    this.muted = false,
  });

  final String name;
  final String? avatarUrl;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl != null && avatarUrl!.isNotEmpty;
    final background = muted
        ? AppStatusColor.neutral.background
        : AppColors.primaryContainer;
    final foreground = muted ? AppColors.textSecondary : AppColors.primary;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: background,
      backgroundImage: hasAvatar ? NetworkImage(avatarUrl!) : null,
      child: hasAvatar
          ? null
          : Text(
              _initials(name),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

/// Data e hora, local e valor, cada um com ícone, etiqueta e valor.
class _JobFactsCard extends StatelessWidget {
  const _JobFactsCard({
    required this.dateTimeLabel,
    required this.locationLabel,
    required this.priceLabel,
    this.onOpenMap,
    this.muted = false,
  });

  final String dateTimeLabel;
  final String locationLabel;
  final String priceLabel;

  /// Abre a morada exata no mapa. `null` quando não há coordenadas.
  final VoidCallback? onOpenMap;

  /// Trabalho cancelado ou expirado: tudo a cinzento.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _FactRow(
            icon: Icons.calendar_today_outlined,
            label: 'Data e hora',
            value: dateTimeLabel,
            muted: muted,
          ),
          const Divider(height: 1, color: AppColors.divider),
          _FactRow(
            icon: Icons.location_on_outlined,
            label: 'Local',
            value: locationLabel,
            muted: muted,
            action: onOpenMap == null
                ? null
                : _InlineLink(
                    label: 'Abrir localização no mapa',
                    onPressed: onOpenMap!,
                  ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          _FactRow(
            icon: Icons.euro_rounded,
            label: 'Valor',
            value: priceLabel,
            muted: muted,
          ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.icon,
    required this.label,
    required this.value,
    this.action,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? action;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: AppSizes.infoRowIcon,
            color: muted ? AppColors.textSecondary : AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  value,
                  style: textTheme.bodyMedium?.copyWith(
                    color: muted
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineLink extends StatelessWidget {
  const _InlineLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: Alignment.centerLeft,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Cliente com "Falar por WhatsApp" ao lado (único contacto da app).
class _ClientWhatsAppCard extends StatelessWidget {
  const _ClientWhatsAppCard({
    required this.name,
    required this.avatarUrl,
    required this.onWhatsApp,
  });

  final String name;
  final String? avatarUrl;

  /// `null` quando o cliente não tem telefone.
  final VoidCallback? onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final displayName = name.isNotEmpty ? name : 'Cliente';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          _InitialsAvatar(name: displayName, avatarUrl: avatarUrl),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Cliente',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          AppWhatsAppButton(onPressed: onWhatsApp, compact: true),
        ],
      ),
    );
  }
}

/// Cartão "Equipa": vagas preenchidas, um círculo por vaga, candidatos por
/// decidir e "Ver equipa" (lobby).
class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.team, required this.onViewTeam});

  final WorkerJobTeamViewData team;
  final VoidCallback onViewTeam;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final pillColor = AppStatusColor.waiting;
    final slots = [
      for (var i = 0; i < team.memberNames.length; i++)
        _InitialsAvatar(
          name: team.memberNames[i],
          avatarUrl: i < team.memberAvatarUrls.length
              ? team.memberAvatarUrls[i]
              : null,
          size: AppSizes.teamSlot,
        ),
      for (var i = 0; i < team.emptySlots; i++)
        Container(
          width: AppSizes.teamSlot,
          height: AppSizes.teamSlot,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.divider),
          ),
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Equipa',
                  style: textTheme.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (team.filledLabel != null)
                Text(
                  team.filledLabel!,
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          if (slots.isNotEmpty || team.pendingLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: slots,
                  ),
                ),
                if (team.pendingLabel != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: pillColor.background,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        team.pendingLabel!,
                        textAlign: TextAlign.center,
                        style: textTheme.labelMedium?.copyWith(
                          color: pillColor.foreground,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: onViewTeam,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.divider),
              minimumSize: const Size.fromHeight(AppSizes.compactButtonHeight),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
            ),
            child: const Text('Ver equipa'),
          ),
        ],
      ),
    );
  }
}

/// Aviso da regra do dia anterior + "Remarcar" e "Cancelar".
class _RescheduleCancelRow extends StatelessWidget {
  const _RescheduleCancelRow({
    required this.reschedulePending,
    required this.proposingReschedule,
    required this.cancelling,
    required this.cancelBlockedBy24h,
    required this.rescheduleBlocked,
    required this.onProposeReschedule,
    required this.onCancelJob,
  });

  final bool reschedulePending;
  final bool proposingReschedule;
  final bool cancelling;
  final bool cancelBlockedBy24h;
  final bool rescheduleBlocked;
  final VoidCallback onProposeReschedule;
  final VoidCallback onCancelJob;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final danger = AppStatusColor.cancelled.foreground;
    final canReschedule =
        !(reschedulePending || proposingReschedule || rescheduleBlocked);
    final canCancel = !(reschedulePending || cancelling || cancelBlockedBy24h);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.input),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: AppSizes.inlineIcon,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Só podes remarcar ou cancelar até ao dia anterior ao trabalho.',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: canReschedule ? onProposeReschedule : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  backgroundColor: AppColors.surface,
                  side: const BorderSide(color: AppColors.divider),
                  minimumSize: const Size.fromHeight(
                    AppSizes.compactButtonHeight,
                  ),
                  shape: shape,
                ),
                child: const Text('Remarcar'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton(
                onPressed: canCancel ? onCancelJob : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: danger,
                  backgroundColor: AppColors.surface,
                  side: BorderSide(
                    color: canCancel
                        ? AppStatusColor.cancelled.background
                        : AppColors.divider,
                  ),
                  minimumSize: const Size.fromHeight(
                    AppSizes.compactButtonHeight,
                  ),
                  shape: shape,
                ),
                child: const Text('Cancelar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Cancelado ou expirado (design A1, segunda coluna) ──────────────────────

class _InactiveJobBody extends StatelessWidget {
  const _InactiveJobBody({
    required this.inactive,
    required this.dateTimeLabel,
    required this.priceLabel,
    required this.clientName,
    required this.clientAvatarUrl,
    required this.onBrowseAvailableJobs,
  });

  final WorkerInactiveJobViewData inactive;
  final String dateTimeLabel;
  final String priceLabel;
  final String clientName;
  final String? clientAvatarUrl;
  final VoidCallback onBrowseAvailableJobs;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = inactive.expired
        ? AppStatusColor.neutral
        : AppStatusColor.cancelled;
    final displayName = clientName.isNotEmpty ? clientName : 'Cliente';

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppStaggeredEntrance(
                  index: 0,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: color.background,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          inactive.expired
                              ? Icons.hourglass_disabled_rounded
                              : Icons.event_busy_outlined,
                          color: color.foreground,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                inactive.title,
                                style: textTheme.titleSmall?.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (inactive.body.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  inactive.body,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppStaggeredEntrance(
                  index: 1,
                  child: _JobFactsCard(
                    dateTimeLabel: dateTimeLabel,
                    locationLabel: inactive.areaLabel,
                    priceLabel: priceLabel,
                    muted: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppStaggeredEntrance(
                  index: 2,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        _InitialsAvatar(
                          name: displayName,
                          avatarUrl: clientAvatarUrl,
                          muted: true,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: textTheme.titleSmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              Text(
                                'Cliente',
                                style: textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _BottomBar(
          child: OutlinedButton(
            onPressed: onBrowseAvailableJobs,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.divider),
              minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
            ),
            child: const Text('Ver pedidos disponíveis'),
          ),
        ),
      ],
    );
  }
}

// ── Concluído (design A1, terceira coluna) ─────────────────────────────────

class _CompletedJobBody extends StatelessWidget {
  const _CompletedJobBody({
    required this.data,
    required this.completed,
    required this.onWorkPhotoTap,
  });

  final WorkerMyJobDetailViewData data;
  final WorkerCompletedJobViewData completed;
  final void Function(List<String> urls, int index) onWorkPhotoTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasPhotos =
        completed.beforePhotoUrls.isNotEmpty ||
        completed.afterPhotoUrls.isNotEmpty;
    final clientName = data.clientName.isNotEmpty ? data.clientName : 'Cliente';
    final success = AppStatusColor.success;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppStaggeredEntrance(
            index: 0,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: success.background,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: AppSizes.heroIcon,
                    color: success.foreground,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Trabalho concluído',
                    style: textTheme.titleMedium?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (completed.metaLabel.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      completed.metaLabel,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (hasPhotos) ...[
            const SizedBox(height: AppSpacing.sm),
            AppStaggeredEntrance(
              index: 1,
              child: Row(
                children: [
                  Expanded(
                    child: _WorkPhotoTile(
                      label: 'Antes',
                      urls: completed.beforePhotoUrls,
                      onTap: onWorkPhotoTap,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _WorkPhotoTile(
                      label: 'Depois',
                      urls: completed.afterPhotoUrls,
                      onTap: onWorkPhotoTap,
                      highlighted: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppStaggeredEntrance(
            index: 2,
            child: Text(
              'Avaliações',
              style: textTheme.titleMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppStaggeredEntrance(
            index: 3,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  _RatingTargetRow(
                    jobId: data.jobId,
                    rateeId: data.clientId,
                    name: clientName,
                    avatarUrl: data.clientAvatarUrl,
                    roleLabel: 'Cliente',
                    actionTitle: 'Avaliar o cliente',
                  ),
                  for (final helper in data.helpersForRating) ...[
                    const Divider(height: 1, color: AppColors.divider),
                    _RatingTargetRow(
                      jobId: data.jobId,
                      rateeId: helper.workerId,
                      name: helper.fullName,
                      roleLabel: 'Ajudante',
                      actionTitle: 'Avaliar: ${helper.fullName}',
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (completed.receivedReview != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AppStaggeredEntrance(
              index: 4,
              child: _ReceivedReviewCard(review: completed.receivedReview!),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkPhotoTile extends StatelessWidget {
  const _WorkPhotoTile({
    required this.label,
    required this.urls,
    required this.onTap,
    this.highlighted = false,
  });

  /// Proporção das miniaturas de "Antes" e "Depois" no design.
  static const double _aspectRatio = 1.35;

  final String label;
  final List<String> urls;
  final void Function(List<String> urls, int index) onTap;

  /// "Depois" leva o verde claro enquanto não há foto.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = urls.isNotEmpty;
    return Semantics(
      button: hasPhoto,
      label: hasPhoto ? 'Fotos de $label' : 'Sem fotos de $label',
      child: AspectRatio(
        aspectRatio: _aspectRatio,
        child: Material(
          color: highlighted
              ? AppStatusColor.success.background
              : AppStatusColor.neutral.background,
          borderRadius: BorderRadius.circular(AppRadius.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: hasPhoto ? () => onTap(urls, 0) : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasPhoto)
                  Image.network(urls.first, fit: BoxFit.cover, cacheWidth: 600),
                Positioned(
                  left: AppSpacing.xs,
                  bottom: AppSpacing.xs,
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: hasPhoto
                          ? BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                            )
                          : null,
                      child: Text(
                        urls.length > 1 ? '$label · ${urls.length}' : label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Uma linha de "Avaliações": "Avaliar o cliente" com seta enquanto falta
/// avaliar; nome, "avaliação enviada" e estrelas depois. Mantida como
/// ConsumerStatefulWidget auto-contido (mesma decisão do antigo
/// _PrincipalRatingCard): evita passar o estado de cada avaliação
/// (myRatingForJobAndRateeProvider) pelo ViewData.
class _RatingTargetRow extends ConsumerStatefulWidget {
  const _RatingTargetRow({
    required this.jobId,
    required this.rateeId,
    required this.name,
    required this.roleLabel,
    required this.actionTitle,
    this.avatarUrl,
  });

  final String jobId;
  final String rateeId;
  final String name;
  final String roleLabel;
  final String actionTitle;
  final String? avatarUrl;

  @override
  ConsumerState<_RatingTargetRow> createState() => _RatingTargetRowState();
}

class _RatingTargetRowState extends ConsumerState<_RatingTargetRow> {
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ratingAsync = ref.watch(
      myRatingForJobAndRateeProvider((widget.jobId, widget.rateeId)),
    );
    final existing = ratingAsync.asData?.value;
    final loaded = ratingAsync.hasValue;
    final canRate = loaded && existing == null;

    return Material(
      color: canRate ? AppColors.primaryContainer : AppColors.surface,
      child: InkWell(
        onTap: canRate ? _showSheet : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              _InitialsAvatar(
                name: widget.name,
                avatarUrl: widget.avatarUrl,
                muted: existing != null,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing != null ? widget.name : widget.actionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      existing != null
                          ? '${widget.roleLabel} · avaliação enviada'
                          : (widget.roleLabel == 'Cliente'
                                ? widget.name
                                : widget.roleLabel),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (existing != null)
                Semantics(
                  label: '${existing.stars} de 5 estrelas',
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        5,
                        (i) => Icon(
                          i < existing.stars
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: AppSizes.ratingStar,
                          color: AppColors.logoAccent,
                        ),
                      ),
                    ),
                  ),
                )
              else if (canRate)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSheet() async {
    final submitted = await showSubmitRatingSheet(
      context: context,
      title: widget.actionTitle,
      successMessage: 'Avaliação enviada!',
      onSubmit: (stars, comment) async {
        await ref
            .read(ratingRepositoryProvider)
            .submitPrincipalRating(
              jobId: widget.jobId,
              rateeId: widget.rateeId,
              stars: stars,
              comment: comment,
            );
      },
    );
    if (submitted != true || !mounted) return;
    ref.invalidate(
      myRatingForJobAndRateeProvider((widget.jobId, widget.rateeId)),
    );
    // "O que falta fazer" do dashboard conta as avaliações dadas.
    ref.invalidate(myRatingsGivenProvider);
  }
}

/// "A Sofia avaliou-te com 5" e o comentário.
class _ReceivedReviewCard extends StatelessWidget {
  const _ReceivedReviewCard({required this.review});

  final WorkerReceivedReviewViewData review;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final comment = review.comment?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.star_outline_rounded,
            size: AppSizes.infoRowIcon,
            color: AppColors.logoAccent,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${review.authorFirstName} avaliou-te com ${review.stars}',
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                if (comment.isNotEmpty)
                  Text(
                    '"$comment"',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const double _labelColumnWidth = AppSpacing.xl * 3 + AppSpacing.md;

class _InformationRow extends StatelessWidget {
  const _InformationRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // Coluna de etiquetas com largura fixa e valores alinhados à esquerda:
    // todos os valores começam na mesma vertical, mesmo os que ocupam
    // várias linhas (morada, valor com intervalo).
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _labelColumnWidth,
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            value,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _HelpersActionButton extends StatelessWidget {
  const _HelpersActionButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          textStyle: textTheme.labelMedium,
        ),
        icon: const Icon(Icons.group_add_outlined),
        label: const Text('Preciso de ajudantes'),
      ),
    );
  }
}

class _RescheduleBanner extends StatelessWidget {
  const _RescheduleBanner({
    required this.proposedByMe,
    required this.label,
    required this.accepting,
    required this.rejecting,
    required this.onAccept,
    required this.onReject,
  });

  final bool proposedByMe;
  final String label;
  final bool accepting;
  final bool rejecting;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = AppStatusColor.waiting;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.event_repeat, color: color.foreground, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  proposedByMe
                      ? 'À espera de resposta à remarcação que propuseste para $label'
                            .trim()
                      : 'O cliente propôs remarcar para $label'.trim(),
                  style: textTheme.bodyMedium?.copyWith(
                    color: color.foreground,
                  ),
                ),
              ),
            ],
          ),
          if (!proposedByMe) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: accepting ? null : onAccept,
                    child: accepting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Aceitar nova data'),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: OutlinedButton(
                    onPressed: rejecting ? null : onReject,
                    child: const Text('Recusar'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final AppStatusColor color;
  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Icon(icon, color: color.foreground, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodyMedium?.copyWith(color: color.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientContactCard extends StatelessWidget {
  const _ClientContactCard({
    required this.name,
    required this.avatarUrl,
    required this.phone,
    required this.onCallPressed,
  });

  final String name;
  final String? avatarUrl;
  final String phone;
  final VoidCallback onCallPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UserAvatarWithName(
            name: name,
            avatarUrl: avatarUrl,
            radius: 22,
            fallbackLabel: 'Cliente',
          ),
          const SizedBox(height: AppSpacing.sm),
          AppWhatsAppButton(onPressed: phone.isEmpty ? null : onCallPressed),
        ],
      ),
    );
  }
}

class _DescriptionSection extends StatelessWidget {
  const _DescriptionSection({
    required this.description,
    required this.photoUrls,
    required this.onPhotoTap,
    this.showTitle = true,
  });

  final String description;
  final List<String> photoUrls;
  final ValueChanged<int> onPhotoTap;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          Text(
            'Descrição',
            style: textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (description.isNotEmpty)
          Text(
            description,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
          ),
        if (photoUrls.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photoUrls.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => onPhotoTap(index),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  child: Image.network(
                    photoUrls[index],
                    width: 88,
                    height: 88,
                    cacheWidth: 360,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Cabeçalho comum aos estados não-Flow6 ─────────────────────────────────

class _JobSummaryCard extends StatelessWidget {
  const _JobSummaryCard({required this.data});

  final WorkerMyJobDetailViewData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _InformationRow(label: 'Serviço', value: data.serviceLabel),
          const SizedBox(height: AppSpacing.sm),
          _InformationRow(label: 'Data', value: data.dateLabel),
          if (data.addressLabel.isNotEmpty ||
              data.locationLat != 0 ||
              data.locationLng != 0) ...[
            const SizedBox(height: AppSpacing.sm),
            AddressMapLink(
              address: data.addressLabel,
              lat: data.locationLat,
              lng: data.locationLng,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _InformationRow(
            label: 'Urgência',
            value: data.urgent ? 'Urgente' : 'Normal',
          ),
          if (data.sizeLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _InformationRow(label: 'Dimensão', value: data.sizeLabel!),
          ],
        ],
      ),
    );
  }
}

class _ProposalSummaryCard extends StatelessWidget {
  const _ProposalSummaryCard({required this.data});

  final WorkerMyJobDetailViewData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A minha proposta',
          style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              _InformationRow(
                label: data.priceRowLabel,
                value: data.hourlyRateLabel,
              ),
              if (data.estimatedHoursLabel != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _InformationRow(
                  label: data.durationRowLabel,
                  value: data.estimatedHoursLabel!,
                ),
              ],
              if (data.estimatedTotalLabel.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _InformationRow(
                  label: 'Total estimado',
                  value: data.estimatedTotalLabel,
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              _InformationRow(label: 'Pessoas', value: '${data.peopleNeeded}'),
              if (data.notes != null && data.notes!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _InformationRow(label: 'Notas', value: data.notes!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// "Tempo em curso" (design 7): relógio a contar desde o início, com a hora
/// de início e a estimativa da proposta. Atualiza de segundo a segundo.
class _WorkTimerCard extends StatefulWidget {
  const _WorkTimerCard({
    required this.startedAt,
    this.estimatedHoursLabel,
    this.title = 'Tempo em curso',
  });

  final DateTime startedAt;
  final String? estimatedHoursLabel;

  /// "Tempo em curso", ou "Dia 2 de 3" num trabalho em vários dias.
  final String title;

  @override
  State<_WorkTimerCard> createState() => _WorkTimerCardState();
}

class _WorkTimerCardState extends State<_WorkTimerCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _clock(Duration d) {
    final seconds = d.isNegative ? 0 : d.inSeconds;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return '$h:${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const color = AppStatusColor.info;
    final started = widget.startedAt.toLocal();
    final startedLabel =
        'Iniciado às ${started.hour.toString().padLeft(2, '0')}:${started.minute.toString().padLeft(2, '0')}';
    final elapsed = DateTime.now().difference(widget.startedAt);

    return Semantics(
      label: widget.title,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: color.background,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: textTheme.labelMedium?.copyWith(
                      color: color.foreground,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  ExcludeSemantics(
                    child: Text(
                      _clock(elapsed),
                      style: textTheme.displaySmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  startedLabel,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (widget.estimatedHoursLabel != null)
                  Text(
                    'Estimado ${widget.estimatedHoursLabel}',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Entre dias: o dia atual terminou e o próximo ainda não começou.
class _DayPausedCard extends StatelessWidget {
  const _DayPausedCard({required this.workDays});

  final WorkerWorkDaysViewData workDays;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const color = AppStatusColor.neutral;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            workDays.headerLabel,
            style: textTheme.labelMedium?.copyWith(color: color.foreground),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Dia ${workDays.dayNumber} terminado',
            style: textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Tempo registado: ${workDays.workedTotalLabel}. Quando voltares, começa o dia ${workDays.dayNumber + 1}.',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lista "Dias de trabalho" com o total registado.
class _WorkDaysCard extends StatelessWidget {
  const _WorkDaysCard({required this.workDays});

  final WorkerWorkDaysViewData workDays;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Dias de trabalho',
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                workDays.workedTotalLabel,
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final row in workDays.rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                children: [
                  Icon(
                    row.current
                        ? Icons.radio_button_checked_rounded
                        : row.planned
                        ? Icons.radio_button_unchecked_rounded
                        : Icons.check_circle_rounded,
                    size: AppSizes.infoRowIcon,
                    color: row.planned
                        ? AppColors.textSecondary
                        : row.current
                        ? AppStatusColor.info.foreground
                        : AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    row.label,
                    style: textTheme.bodyMedium?.copyWith(
                      color: row.planned
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                      fontWeight: row.current ? FontWeight.w700 : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      row.detail,
                      textAlign: TextAlign.end,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Valor fechado": o total, o que inclui e o aviso de que não muda.
class _FixedValueCard extends StatelessWidget {
  const _FixedValueCard({required this.fixedValue});

  final WorkerFixedValueViewData fixedValue;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Valor fechado',
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
              Text(
                fixedValue.valueLabel,
                style: textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (fixedValue.includesLabel != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              fixedValue.includesLabel!,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Não muda com as horas nem com os dias.',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
