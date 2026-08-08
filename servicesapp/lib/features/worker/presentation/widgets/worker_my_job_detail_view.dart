import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/theme/app_status_presentation.dart';
import '../../../../core/widgets/address_map_link.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_status_badge.dart';
import '../../../../core/widgets/primary_action_button.dart';
import '../../../../core/widgets/status_timeline.dart';
import '../../../../core/widgets/user_avatar_with_name.dart';
import '../../../ratings/application/rating_providers.dart';
import '../../../ratings/presentation/rating_sheet.dart';

/// Dados de apresentação do ecrã "O meu trabalho" (Flow 6 + estados
/// preservados de sessões anteriores).
///
/// A integração (worker_my_job_detail_screen.dart) mapeia os models reais
/// (JobProposal/JobRequest) para esta estrutura. Este ecrã não consulta
/// providers, repositories ou Supabase diretamente — a única exceção é
/// _PrincipalRatingCard, que já era um ConsumerWidget auto-contido antes
/// desta separação (mesmo padrão usado noutros pontos da app, ex.
/// _RatingChip em worker_jobs_screen.dart).
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

  final String clientId;
  final String clientName;
  final String? clientAvatarUrl;
  final String clientPhone;

  final RescheduleStatus? rescheduleStatus;
  final bool rescheduleProposedByMe;
  final String proposedRescheduleLabel;

  final bool cancelBlockedBy24h;

  final List<AcceptedHelper> helpersForRating;

  final bool proposingReschedule;
  final bool acceptingReschedule;
  final bool rejectingReschedule;
  final bool cancellingJob;
  final bool withdrawing;
}

class WorkerMyJobDetailScreen extends StatefulWidget {
  const WorkerMyJobDetailScreen({
    required this.data,
    required this.onBack,
    required this.onCallClientPressed,
    required this.onRequestHelpersPressed,
    required this.onMarkCompleted,
    required this.onProposeReschedule,
    required this.onAcceptReschedule,
    required this.onRejectReschedule,
    required this.onCancelJob,
    required this.onWithdrawProposal,
    required this.onPhotoTap,
    super.key,
    this.onCompletionFeedbackFinished,
  });

  final WorkerMyJobDetailViewData data;

  final VoidCallback onBack;
  final VoidCallback onCallClientPressed;
  final VoidCallback onRequestHelpersPressed;

  /// Deve devolver true apenas depois da RPC (mark_job_done) confirmar
  /// sucesso — o AlertDialog de confirmação já vive dentro deste callback,
  /// no wrapper (ver worker_my_job_detail_screen.dart _markCompleted).
  final Future<bool> Function() onMarkCompleted;

  final VoidCallback onProposeReschedule;
  final VoidCallback onAcceptReschedule;
  final VoidCallback onRejectReschedule;
  final VoidCallback onCancelJob;
  final VoidCallback onWithdrawProposal;
  final ValueChanged<int> onPhotoTap;

  /// Executado depois do AppSuccessFeedback — navega para /worker/home.
  final VoidCallback? onCompletionFeedbackFinished;

  @override
  State<WorkerMyJobDetailScreen> createState() {
    return _WorkerMyJobDetailScreenState();
  }
}

class _WorkerMyJobDetailScreenState extends State<WorkerMyJobDetailScreen> {
  bool _completing = false;
  bool _showSuccessFeedback = false;
  Timer? _successTimer;

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

  @override
  void dispose() {
    _successTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final textTheme = Theme.of(context).textTheme;
    final isConfirmed = data.proposalStatus == ProposalStatus.accepted &&
        data.jobStatus == JobStatus.confirmed;

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
        title: Text(
          'Trabalho',
          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Center(
              child: AppStatusBadge.fromPresentation(
                presentation: data.statusPresentation,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          isConfirmed ? _buildConfirmedBody(context) : _buildOtherBody(context),
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

  // ── Flow 6 — accepted + confirmed ("Trabalho agendado") ──────────────────

  Widget _buildConfirmedBody(BuildContext context) {
    final data = widget.data;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppStaggeredEntrance(
                  index: 0,
                  child: StatusTimeline(steps: data.timelineSteps),
                ),
                const SizedBox(height: AppSpacing.md),
                AppStaggeredEntrance(
                  index: 1,
                  child: Row(
                    children: [
                      Expanded(
                        child: UserAvatarWithName(
                          name: data.clientName,
                          avatarUrl: data.clientAvatarUrl,
                          radius: 22,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _CallButton(
                        enabled: data.clientPhone.isNotEmpty,
                        onPressed: widget.onCallClientPressed,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppStaggeredEntrance(
                  index: 2,
                  child: _JobInformationCard(
                    serviceLabel: data.serviceLabel,
                    areaLabel: data.sizeLabel ?? 'Não especificado',
                    dateTimeLabel: data.confirmedScheduleLabel,
                    locationLabel: data.addressLabel,
                    priceLabel: data.hourlyRateLabel,
                  ),
                ),
                if (data.rescheduleStatus == RescheduleStatus.pending) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppStaggeredEntrance(
                    index: 3,
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
                  index: 4,
                  child: _HelpersActionButton(
                    onPressed: widget.onRequestHelpersPressed,
                  ),
                ),
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
                    onProposeReschedule: widget.onProposeReschedule,
                    onCancelJob: widget.onCancelJob,
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          color: AppColors.background,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: PrimaryActionButton(
            label: 'Marcar como concluído',
            isLoading: _completing,
            onPressed: _completing ? null : _handleMarkCompleted,
          ),
        ),
      ],
    );
  }

  // ── Outros estados (rejected/superseded/pending, e accepted fora de
  // confirmed) — conteúdo/lógica preservados de sessões anteriores, só com
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
            AppStaggeredEntrance(
              index: 0,
              child: _JobSummaryCard(data: data),
            ),
            const SizedBox(height: AppSpacing.md),
            AppStaggeredEntrance(
              index: 1,
              child: Text(
                'Descrição',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            AppStaggeredEntrance(
              index: 1,
              child: _DescriptionSection(
                description: data.description,
                photoUrls: data.photoUrls,
                onPhotoTap: widget.onPhotoTap,
                showTitle: false,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppStaggeredEntrance(
              index: 2,
              child: _ProposalSummaryCard(data: data),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppStaggeredEntrance(
              index: 3,
              child: Text(
                'Estado do pedido',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppStaggeredEntrance(
              index: 4,
              child: StatusTimeline(steps: data.timelineSteps),
            ),
            const SizedBox(height: AppSpacing.md),
            AppStaggeredEntrance(
              index: 5,
              child: _branchBody(context),
            ),
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
          Text('Cliente', style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          _ClientContactCard(
            name: data.clientName,
            avatarUrl: data.clientAvatarUrl,
            phone: data.clientPhone,
            onCallPressed: widget.onCallClientPressed,
          ),
          const SizedBox(height: AppSpacing.md),
          // jobStatus == confirmed nunca chega aqui — esse caso é servido
          // por _buildConfirmedBody (Flow 6). Só awaitingConfirmation e
          // completed restam dentro deste ramo "accepted".
          if (data.jobStatus == JobStatus.awaitingConfirmation)
            _InfoBanner(
              icon: Icons.hourglass_top_rounded,
              color: AppStatusColor.info,
              message:
                  'Aguarda confirmação do cliente. Já marcaste este trabalho como concluído.',
            )
          else if (data.jobStatus == JobStatus.completed)
            _CompletedSection(
              jobId: data.jobId,
              clientId: data.clientId,
              helpers: data.helpersForRating,
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
              style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
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
          message: 'A tua proposta está a aguardar resposta do cliente.',
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

// ── Flow 6 building blocks ────────────────────────────────────────────────

class _CallButton extends StatelessWidget {
  const _CallButton({required this.onPressed, this.enabled = true});

  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      tooltip: 'Contactar via WhatsApp',
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: AppColors.primaryContainer,
        foregroundColor: AppColors.primary,
        disabledBackgroundColor: AppColors.divider,
        disabledForegroundColor: AppColors.textSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
      ),
      icon: const Icon(Icons.chat_outlined),
    );
  }
}

class _JobInformationCard extends StatelessWidget {
  const _JobInformationCard({
    required this.serviceLabel,
    required this.areaLabel,
    required this.dateTimeLabel,
    required this.locationLabel,
    required this.priceLabel,
  });

  final String serviceLabel;
  final String areaLabel;
  final String dateTimeLabel;
  final String locationLabel;
  final String priceLabel;

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
          _InformationRow(label: 'Serviço', value: '$serviceLabel · $areaLabel'),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: AppSpacing.sm),
          _InformationRow(label: 'Data e hora', value: dateTimeLabel),
          const SizedBox(height: AppSpacing.sm),
          _InformationRow(label: 'Local', value: locationLabel),
          const SizedBox(height: AppSpacing.sm),
          _InformationRow(label: 'Valor', value: priceLabel, highlighted: true),
        ],
      ),
    );
  }
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: textTheme.bodyMedium?.copyWith(
              color: highlighted ? AppColors.primary : AppColors.textPrimary,
              fontWeight: highlighted ? FontWeight.w700 : null,
            ),
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

class _RescheduleCancelRow extends StatelessWidget {
  const _RescheduleCancelRow({
    required this.reschedulePending,
    required this.proposingReschedule,
    required this.cancelling,
    required this.cancelBlockedBy24h,
    required this.onProposeReschedule,
    required this.onCancelJob,
  });

  final bool reschedulePending;
  final bool proposingReschedule;
  final bool cancelling;
  final bool cancelBlockedBy24h;
  final VoidCallback onProposeReschedule;
  final VoidCallback onCancelJob;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (reschedulePending || proposingReschedule)
                    ? null
                    : onProposeReschedule,
                icon: const Icon(Icons.event_repeat),
                label: const Text('Remarcar'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (reschedulePending || cancelling || cancelBlockedBy24h)
                    ? null
                    : onCancelJob,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppStatusColor.cancelled.foreground,
                ),
                icon: const Icon(Icons.close),
                label: const Text('Cancelar'),
              ),
            ),
          ],
        ),
        if (cancelBlockedBy24h) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Cancelamento disponível até 24h antes da data confirmada.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ],
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
                      ? 'Aguarda resposta à remarcação que propuseste para $label'
                          .trim()
                      : 'O cliente propôs remarcar para $label'.trim(),
                  style: textTheme.bodyMedium?.copyWith(color: color.foreground),
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
          UserAvatarWithName(name: name, avatarUrl: avatarUrl, radius: 22),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: phone.isEmpty ? null : onCallPressed,
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Contactar via WhatsApp'),
          ),
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
            style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
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
          if (data.addressLabel.isNotEmpty || data.locationLat != 0 || data.locationLng != 0) ...[
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
              _InformationRow(label: 'Taxa/hora', value: data.hourlyRateLabel),
              if (data.estimatedHoursLabel != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _InformationRow(
                  label: 'Horas estimadas',
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

class _CompletedSection extends StatelessWidget {
  const _CompletedSection({
    required this.jobId,
    required this.clientId,
    required this.helpers,
  });

  final String jobId;
  final String clientId;
  final List<AcceptedHelper> helpers;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _InfoBanner(
          icon: Icons.task_alt_rounded,
          color: AppStatusColor.success,
          message: 'Trabalho concluído. Obrigado pelo teu trabalho!',
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Deixa a tua avaliação',
          style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        _PrincipalRatingCard(
          jobId: jobId,
          rateeId: clientId,
          title: 'Avaliar o cliente',
          submittedLabel: 'Cliente avaliado ✓',
        ),
        for (final helper in helpers)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: _PrincipalRatingCard(
              jobId: jobId,
              rateeId: helper.workerId,
              title: 'Avaliar: ${helper.fullName}',
              submittedLabel: '${helper.fullName} avaliado ✓',
            ),
          ),
      ],
    );
  }
}

/// Mantido como ConsumerStatefulWidget auto-contido (mesma decisão já usada
/// para _RatingChip noutros ecrãs) — evita ter de threading do estado de
/// avaliação (myRatingForJobAndRateeProvider) através do ViewData.
class _PrincipalRatingCard extends ConsumerStatefulWidget {
  const _PrincipalRatingCard({
    required this.jobId,
    required this.rateeId,
    required this.title,
    required this.submittedLabel,
  });

  final String jobId;
  final String rateeId;
  final String title;
  final String submittedLabel;

  @override
  ConsumerState<_PrincipalRatingCard> createState() {
    return _PrincipalRatingCardState();
  }
}

class _PrincipalRatingCardState extends ConsumerState<_PrincipalRatingCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratingAsync = ref.watch(
      myRatingForJobAndRateeProvider((widget.jobId, widget.rateeId)),
    );

    return ratingAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const SizedBox.shrink(),
      data: (existing) {
        if (existing != null) {
          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    widget.submittedLabel,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textPrimary),
                  ),
                ),
                Row(
                  children: List.generate(
                    5,
                    (i) => Icon(
                      i < existing.stars
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 16,
                      color: Colors.amber,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textPrimary),
                ),
              ),
              FilledButton.tonal(
                onPressed: _showSheet,
                child: const Text('Avaliar'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSheet() async {
    final submitted = await showRatingSheet(
      context: context,
      title: widget.title,
      onSubmit: (stars, comment) async {
        await ref.read(ratingRepositoryProvider).submitPrincipalRating(
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
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Avaliação enviada!')));
  }
}
