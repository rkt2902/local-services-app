import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/theme/app_status_presentation.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_status_badge.dart';
import '../../../../core/widgets/primary_action_button.dart';
import '../../../../core/widgets/user_avatar_with_name.dart';

/// Estado puramente visual de UMA secção (um `HelpRequest`) do lobby — não
/// substitui `HelpRequestStatus`. Um job pode, em teoria, ter mais do que
/// um `HelpRequest` (o schema não o impede, embora a intenção do MVP seja
/// 1:1 — ver improvements.md), por isso o lobby continua a mostrar uma
/// secção por `HelpRequest`, tal como o ecrã original.
enum WorkerHelpSectionDisplayMode { awaitingClientApproval, active, filled }

class WorkerHelpLobbyViewData {
  const WorkerHelpLobbyViewData({
    required this.jobReferenceLabel,
    required this.responsibleName,
    required this.sections,
    this.responsibleAvatarUrl,
  });

  /// Ex.: "Job #a1b2c3d4".
  final String jobReferenceLabel;
  final String responsibleName;
  final String? responsibleAvatarUrl;

  /// Vazia = nenhum `HelpRequest` foi pedido ainda para este job.
  final List<HelpRequestSectionViewData> sections;
}

class HelpRequestSectionViewData {
  const HelpRequestSectionViewData({
    required this.helpRequestId,
    required this.displayMode,
    required this.statusPresentation,
    required this.filledPlacesLabel,
    required this.filledProgress,
    required this.acceptedHelpers,
    required this.pendingCandidates,
  });

  final String helpRequestId;
  final WorkerHelpSectionDisplayMode displayMode;

  /// Presenter real de `HelpRequestStatus` (app_status_presenters.dart).
  final AppStatusPresentation statusPresentation;

  /// Ex.: "1 de 2 vagas preenchidas" — já formatado pela integração.
  final String filledPlacesLabel;

  /// 0...1, já calculado pela integração.
  final double filledProgress;

  final List<WorkerAcceptedHelperViewData> acceptedHelpers;
  final List<WorkerHelpCandidateViewData> pendingCandidates;
}

class WorkerAcceptedHelperViewData {
  const WorkerAcceptedHelperViewData({
    required this.workerId,
    required this.name,
    required this.equipmentLabel,
    required this.statusPresentation,
    this.avatarUrl,
    this.ratingLabel,
    this.rateLabel,
  });

  final String workerId;
  final String name;
  final String? avatarUrl;

  /// `null` = sem avaliações ainda (oculta a linha, não inventa "0★").
  final String? ratingLabel;
  final String equipmentLabel;

  /// `null` = taxa acordada ainda não definida (não deve acontecer para um
  /// aceite, mas o ecrã não assume).
  final String? rateLabel;

  /// Presenter real de `HelpAcceptanceStatus.accepted`.
  final AppStatusPresentation statusPresentation;
}

class WorkerHelpCandidateViewData {
  const WorkerHelpCandidateViewData({
    required this.applicationId,
    required this.workerId,
    required this.name,
    required this.equipmentLabel,
    required this.statusPresentation,
    required this.actionsBlocked,
    required this.acceptance,
    this.avatarUrl,
    this.ratingLabel,
    this.blockedReasonLabel,
  });

  final String applicationId;
  final String workerId;
  final String name;
  final String? avatarUrl;
  final String? ratingLabel;
  final String equipmentLabel;

  /// Presenter real de `HelpAcceptanceStatus.pending`.
  final AppStatusPresentation statusPresentation;

  /// `true` quando as vagas já estão preenchidas (ou, defensivamente, quando
  /// o pedido está `awaitingClientApproval` — nesse estado não deveria
  /// existir nenhum candidato pendente, porque a descoberta só mostra
  /// pedidos `open`, mas o ecrã não assume isso e bloqueia de qualquer
  /// forma se algum dia chegar aqui).
  final bool actionsBlocked;
  final String? blockedReasonLabel;

  final AcceptHelperViewData acceptance;
}

class AcceptHelperViewData {
  const AcceptHelperViewData({
    required this.initialRateInput,
    required this.suggestedRateLabel,
    this.estimateLabel,
  });

  /// Valor sugerido, já formatado para preencher o campo (ex.: "12.50").
  final String initialRateInput;

  /// Ex.: "Sugerido: €12.50/hora".
  final String suggestedRateLabel;

  /// Duração/total estimado, já formatado — `null` quando a proposta não
  /// tem horas estimadas definidas (o ecrã não inventa uma duração).
  final String? estimateLabel;
}

class WorkerHelpRequestsLobbyView extends StatefulWidget {
  const WorkerHelpRequestsLobbyView({
    super.key,
    required this.dataAsync,
    required this.onBack,
    required this.onRequestHelpers,
    required this.onAcceptCandidate,
    required this.onRejectCandidate,
    required this.onViewRatings,
    this.rateValidator,
    this.onRetry,
  });

  final AsyncValue<WorkerHelpLobbyViewData> dataAsync;

  final VoidCallback onBack;
  final VoidCallback onRequestHelpers;
  final VoidCallback? onRetry;

  final void Function(String workerId, String name) onViewRatings;

  /// Deve devolver `true` apenas depois de `accept_help_candidate`
  /// confirmar sucesso.
  final Future<bool> Function(String applicationId, String rateInput)
      onAcceptCandidate;

  /// Deve devolver `true` apenas depois de `reject_help_candidate`
  /// confirmar sucesso.
  final Future<bool> Function(String applicationId) onRejectCandidate;

  final String? Function(String?)? rateValidator;

  @override
  State<WorkerHelpRequestsLobbyView> createState() =>
      _WorkerHelpRequestsLobbyViewState();
}

class _WorkerHelpRequestsLobbyViewState
    extends State<WorkerHelpRequestsLobbyView> {
  final Set<String> _processingApplications = {};
  bool _successVisible = false;
  String _successMessage = '';

  Future<void> _openAcceptSheet(WorkerHelpCandidateViewData candidate) async {
    if (_processingApplications.contains(candidate.applicationId)) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (_) => _AcceptHelperBottomSheet(
        candidate: candidate,
        rateValidator: widget.rateValidator,
        onConfirm: (rateInput) =>
            widget.onAcceptCandidate(candidate.applicationId, rateInput),
      ),
    );

    if (!mounted || confirmed != true) return;
    setState(() {
      _successMessage = 'Ajudante adicionado à equipa.';
      _successVisible = true;
    });
  }

  Future<void> _reject(WorkerHelpCandidateViewData candidate) async {
    if (_processingApplications.contains(candidate.applicationId)) return;

    setState(() {
      _processingApplications.add(candidate.applicationId);
      _successVisible = false;
    });

    bool confirmed = false;
    try {
      confirmed = await widget.onRejectCandidate(candidate.applicationId);
    } finally {
      if (!mounted) return;
      setState(() {
        _processingApplications.remove(candidate.applicationId);
        if (confirmed) {
          _successMessage = 'Candidatura recusada.';
          _successVisible = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            widget.dataAsync.when(
              loading: () => _LobbyLoading(onBack: widget.onBack),
              error: (_, _) =>
                  _LobbyError(onBack: widget.onBack, onRetry: widget.onRetry),
              data: (data) => _LobbyContent(
                data: data,
                processingApplications: _processingApplications,
                onBack: widget.onBack,
                onRequestHelpers: widget.onRequestHelpers,
                onViewRatings: widget.onViewRatings,
                onAccept: _openAcceptSheet,
                onReject: _reject,
              ),
            ),
            Positioned.fill(
              child: AppSuccessFeedback(
                visible: _successVisible,
                message: _successMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LobbyContent extends StatelessWidget {
  const _LobbyContent({
    required this.data,
    required this.processingApplications,
    required this.onBack,
    required this.onRequestHelpers,
    required this.onViewRatings,
    required this.onAccept,
    required this.onReject,
  });

  final WorkerHelpLobbyViewData data;
  final Set<String> processingApplications;

  final VoidCallback onBack;
  final VoidCallback onRequestHelpers;
  final void Function(String workerId, String name) onViewRatings;

  final ValueChanged<WorkerHelpCandidateViewData> onAccept;
  final ValueChanged<WorkerHelpCandidateViewData> onReject;

  @override
  Widget build(BuildContext context) {
    var entranceIndex = 0;
    int nextIndex() => entranceIndex++;

    return Column(
      children: [
        _LobbyHeader(onBack: onBack),
        Expanded(
          child: ListView(
            key: const PageStorageKey('worker_help_requests_lobby'),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            children: [
              AppStaggeredEntrance(
                index: nextIndex(),
                child: _ResponsibleCard(data: data),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (data.sections.isEmpty)
                AppStaggeredEntrance(
                  index: nextIndex(),
                  child: _NoHelpRequestState(onRequestHelpers: onRequestHelpers),
                )
              else
                for (final section in data.sections) ...[
                  if (section.displayMode ==
                      WorkerHelpSectionDisplayMode.awaitingClientApproval)
                    AppStaggeredEntrance(
                      index: nextIndex(),
                      child: _AwaitingApprovalCard(
                        presentation: section.statusPresentation,
                      ),
                    )
                  else
                    AppStaggeredEntrance(
                      index: nextIndex(),
                      child: _CapacityCard(
                        filledPlacesLabel: section.filledPlacesLabel,
                        progress: section.filledProgress,
                        statusPresentation: section.statusPresentation,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  if (section.acceptedHelpers.isNotEmpty) ...[
                    const _SectionLabel(label: 'Aceites'),
                    const SizedBox(height: AppSpacing.xs),
                    for (final helper in section.acceptedHelpers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: AppStaggeredEntrance(
                          index: nextIndex(),
                          child: _AcceptedHelperCard(
                            helper: helper,
                            onViewRatings: helper.ratingLabel == null
                                ? null
                                : () => onViewRatings(helper.workerId, helper.name),
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (section.pendingCandidates.isNotEmpty) ...[
                    const _SectionLabel(label: 'Por decidir'),
                    const SizedBox(height: AppSpacing.xs),
                    for (final candidate in section.pendingCandidates)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: AppStaggeredEntrance(
                          index: nextIndex(),
                          child: _CandidateCard(
                            candidate: candidate,
                            processing: processingApplications
                                .contains(candidate.applicationId),
                            onViewRatings: candidate.ratingLabel == null
                                ? null
                                : () =>
                                    onViewRatings(candidate.workerId, candidate.name),
                            onAccept: () => onAccept(candidate),
                            onReject: () => onReject(candidate),
                          ),
                        ),
                      ),
                  ],
                  if (section.acceptedHelpers.isEmpty &&
                      section.pendingCandidates.isEmpty &&
                      section.displayMode !=
                          WorkerHelpSectionDisplayMode.awaitingClientApproval)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Text(
                        'Sem candidatos ainda.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LobbyHeader extends StatelessWidget {
  const _LobbyHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Voltar',
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              'Equipa',
              style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponsibleCard extends StatelessWidget {
  const _ResponsibleCard({required this.data});

  final WorkerHelpLobbyViewData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatarWithName(
                  name: data.responsibleName.isNotEmpty ? data.responsibleName : 'Tu',
                  avatarUrl: data.responsibleAvatarUrl,
                  radius: 20,
                  nameStyle:
                      textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
                ),
                Padding(
                  padding:
                      const EdgeInsets.only(left: AppSpacing.xl + AppSpacing.md),
                  child: Text(
                    'Responsável · ${data.jobReferenceLabel}',
                    style: textTheme.labelMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              'Responsável',
              style: textTheme.labelMedium?.copyWith(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapacityCard extends StatelessWidget {
  const _CapacityCard({
    required this.filledPlacesLabel,
    required this.progress,
    required this.statusPresentation,
  });

  final String filledPlacesLabel;
  final double progress;
  final AppStatusPresentation statusPresentation;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  filledPlacesLabel,
                  style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
                ),
              ),
              AppStatusBadge.fromPresentation(presentation: statusPresentation),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppColors.divider,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _AwaitingApprovalCard extends StatelessWidget {
  const _AwaitingApprovalCard({required this.presentation});

  final AppStatusPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: presentation.color.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: presentation.color.foreground),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_bottom_rounded, color: presentation.color.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppStatusBadge.fromPresentation(presentation: presentation),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'O cliente ainda precisa de aprovar este pedido de ajuda. '
                  'Os candidatos só podem ver e candidatar-se depois da aprovação.',
                  style: textTheme.labelMedium?.copyWith(
                    color: presentation.color.foreground,
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Text(
      label.toUpperCase(),
      style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
    );
  }
}

class _AcceptedHelperCard extends StatelessWidget {
  const _AcceptedHelperCard({required this.helper, required this.onViewRatings});

  final WorkerAcceptedHelperViewData helper;
  final VoidCallback? onViewRatings;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppStatusColor.success.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppStatusColor.success.foreground),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _WorkerSummary(
              name: helper.name,
              avatarUrl: helper.avatarUrl,
              ratingLabel: helper.ratingLabel,
              equipmentLabel: helper.equipmentLabel,
              statusPresentation: helper.statusPresentation,
              onViewRatings: onViewRatings,
            ),
          ),
          if (helper.rateLabel != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AppStatusBadge.fromPresentation(presentation: helper.statusPresentation),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  helper.rateLabel!,
                  style: textTheme.titleMedium?.copyWith(color: AppColors.primary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.processing,
    required this.onViewRatings,
    required this.onAccept,
    required this.onReject,
  });

  final WorkerHelpCandidateViewData candidate;
  final bool processing;
  final VoidCallback? onViewRatings;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final actionsEnabled = !candidate.actionsBlocked && !processing;

    return Opacity(
      opacity: candidate.actionsBlocked ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            _WorkerSummary(
              name: candidate.name,
              avatarUrl: candidate.avatarUrl,
              ratingLabel: candidate.ratingLabel,
              equipmentLabel: candidate.equipmentLabel,
              statusPresentation: candidate.statusPresentation,
              onViewRatings: onViewRatings,
              trailing:
                  AppStatusBadge.fromPresentation(presentation: candidate.statusPresentation),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: PrimaryActionButton(
                    label: processing ? 'A processar...' : 'Aceitar',
                    onPressed: actionsEnabled ? onAccept : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  child: InkWell(
                    onTap: actionsEnabled ? onReject : null,
                    borderRadius: BorderRadius.circular(AppRadius.input),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        border: Border.all(color: AppColors.divider),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.close_rounded,
                        color: actionsEnabled
                            ? AppColors.textSecondary
                            : AppStatusColor.neutral.foreground,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (candidate.actionsBlocked && candidate.blockedReasonLabel != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                candidate.blockedReasonLabel!,
                textAlign: TextAlign.center,
                style:
                    textTheme.labelMedium?.copyWith(color: AppStatusColor.neutral.foreground),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Nome + avatar (cor do anel/fundo consoante o `statusPresentation` — o
/// mesmo `AppStatusColor` já usado nos badges) + rating opcional +
/// equipamento. Partilhado entre candidato pendente, ajudante aceite e o
/// resumo dentro do bottom sheet de aceitação.
class _WorkerSummary extends StatelessWidget {
  const _WorkerSummary({
    required this.name,
    required this.avatarUrl,
    required this.ratingLabel,
    required this.equipmentLabel,
    required this.statusPresentation,
    this.onViewRatings,
    this.trailing,
  });

  final String name;
  final String? avatarUrl;
  final String? ratingLabel;
  final String equipmentLabel;
  final AppStatusPresentation statusPresentation;
  final VoidCallback? onViewRatings;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasAvatar = avatarUrl != null && avatarUrl!.isNotEmpty;
    final initial = name.isNotEmpty ? name.trim()[0].toUpperCase() : '?';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: statusPresentation.color.background,
          backgroundImage: hasAvatar ? NetworkImage(avatarUrl!) : null,
          child: hasAvatar
              ? null
              : Text(
                  initial,
                  style: textTheme.titleMedium
                      ?.copyWith(color: statusPresentation.color.foreground),
                ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
              ),
              if (ratingLabel != null)
                GestureDetector(
                  onTap: onViewRatings,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(
                        ratingLabel!,
                        style: textTheme.labelSmall?.copyWith(color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                equipmentLabel,
                style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.xs),
          trailing!,
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// BOTTOM SHEET DE ACEITAÇÃO
// -----------------------------------------------------------------------------

class _AcceptHelperBottomSheet extends StatefulWidget {
  const _AcceptHelperBottomSheet({
    required this.candidate,
    required this.onConfirm,
    required this.rateValidator,
  });

  final WorkerHelpCandidateViewData candidate;
  final Future<bool> Function(String rateInput) onConfirm;
  final String? Function(String?)? rateValidator;

  @override
  State<_AcceptHelperBottomSheet> createState() => _AcceptHelperBottomSheetState();
}

class _AcceptHelperBottomSheetState extends State<_AcceptHelperBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _rateController;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _rateController = TextEditingController(text: widget.candidate.acceptance.initialRateInput);
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    bool confirmed = false;
    try {
      confirmed = await widget.onConfirm(_rateController.text.trim());
    } finally {
      if (!mounted) return;
      setState(() => _submitting = false);
    }

    if (!mounted || !confirmed) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final acceptance = widget.candidate.acceptance;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md + keyboardInset,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Aceitar candidato',
                style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Confirma a taxa acordada com ${widget.candidate.name}.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.divider),
                ),
                child: _WorkerSummary(
                  name: widget.candidate.name,
                  avatarUrl: widget.candidate.avatarUrl,
                  ratingLabel: widget.candidate.ratingLabel,
                  equipmentLabel: widget.candidate.equipmentLabel,
                  statusPresentation: widget.candidate.statusPresentation,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Taxa acordada (€/hora)',
                  style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              _RateField(
                controller: _rateController,
                suggestedRateLabel: acceptance.suggestedRateLabel,
                validator: widget.rateValidator,
              ),
              if (acceptance.estimateLabel != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    acceptance.estimateLabel!,
                    style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              PrimaryActionButton(
                label: _submitting ? 'A confirmar...' : 'Confirmar e adicionar à equipa',
                onPressed: _submitting ? null : _confirm,
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                child: Text(
                  'Cancelar',
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RateField extends StatelessWidget {
  const _RateField({
    required this.controller,
    required this.suggestedRateLabel,
    required this.validator,
  });

  final TextEditingController controller;
  final String suggestedRateLabel;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.primary),
      ),
      child: Row(
        children: [
          Text('€', style: textTheme.titleLarge?.copyWith(color: AppColors.primary)),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              validator: validator,
              style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              suggestedRateLabel,
              style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// OUTROS ESTADOS
// -----------------------------------------------------------------------------

class _NoHelpRequestState extends StatelessWidget {
  const _NoHelpRequestState({required this.onRequestHelpers});

  final VoidCallback onRequestHelpers;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: AppStatusColor.neutral.background,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.group_off_outlined,
                color: AppStatusColor.neutral.foreground, size: 32),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Sem vagas neste trabalho',
            textAlign: TextAlign.center,
            style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Ainda não pediste ajudantes para este pedido.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onRequestHelpers,
            icon: const Icon(Icons.group_add_outlined, color: AppColors.primary),
            label: Text(
              'Pedir ajudantes',
              style: textTheme.bodyMedium
                  ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.divider),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LobbyLoading extends StatelessWidget {
  const _LobbyLoading({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LobbyHeader(onBack: onBack),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: 4,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, index) => AppSkeletonShimmer(
              child: Container(
                height: index == 0 ? 72 : 108,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LobbyError extends StatelessWidget {
  const _LobbyError({required this.onBack, required this.onRetry});

  final VoidCallback onBack;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        _LobbyHeader(onBack: onBack),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppStatusColor.cancelled.background,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.cloud_off_outlined,
                        color: AppStatusColor.cancelled.foreground),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Não foi possível carregar a equipa.',
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton(
                      onPressed: onRetry,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                        ),
                      ),
                      child: Text(
                        'Tentar novamente',
                        style: textTheme.bodyMedium
                            ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
