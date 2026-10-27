import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/models/job_flow_stage.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/theme/app_status_presentation.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/utils/price_labels.dart';
import '../../../core/widgets/address_map_link.dart';
import '../../../core/widgets/app_whatsapp_button.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../../core/widgets/job_flow_stepper.dart';
import '../../../core/widgets/status_timeline.dart';
import '../../ratings/application/rating_providers.dart';
import '../../ratings/presentation/worker_ratings_sheet.dart';
import '../../worker/application/worker_job_rules.dart';
import '../../worker/application/worker_list_invalidation.dart';
import '../application/help_request_providers.dart';
import '../application/helper_job_state.dart';
import '../data/help_request_model.dart';
import 'widgets/helper_actions.dart';
import '../../../core/widgets/app_toast.dart';

/// "Trabalho como ajudante" — o detalhe de UMA candidatura, visto pelo
/// próprio ajudante (rota `/worker/help/:acceptanceId`, fora do shell).
///
/// Aberto pelo board "Os meus trabalhos" (linhas de ajudante), pelos cartões
/// da tab "As minhas candidaturas" e pelas notificações de ajudante. Lê a
/// candidatura de [myHelpAcceptancesProvider] (sem pedido extra à BD).
class WorkerHelperJobScreen extends ConsumerStatefulWidget {
  const WorkerHelperJobScreen({super.key, required this.acceptanceId});

  final String acceptanceId;

  @override
  ConsumerState<WorkerHelperJobScreen> createState() =>
      _WorkerHelperJobScreenState();
}

class _WorkerHelperJobScreenState extends ConsumerState<WorkerHelperJobScreen> {
  bool _withdrawing = false;

  Future<void> _onRefresh() async {
    ref.invalidate(myHelpAcceptancesProvider);
    await ref.read(myHelpAcceptancesProvider.future).catchError((_) => const <HelpAcceptanceSummary>[]);
  }

  Future<void> _withdraw(HelpAcceptanceSummary acceptance) async {
    final isPending = acceptance.status == HelpAcceptanceStatus.pending;
    final confirmed = await confirmHelperWithdraw(context, isPending: isPending);
    if (!confirmed || !mounted) return;
    final toast = AppToast.of(context);
    setState(() => _withdrawing = true);
    try {
      await ref
          .read(helpRequestRepositoryProvider)
          .withdrawHelpAcceptance(acceptance.id);
      if (!mounted) return;
      // Regra T4 (sem navegação): SnackBar → invalidar. O ecrã fica aberto
      // e passa a mostrar o estado novo.
      toast.show(isPending ? 'Candidatura retirada.' : 'Desististe desta ajuda.');
      invalidateWorkerLists(ref, jobId: acceptance.jobId);
    } catch (e) {
      if (!mounted) return;
      toast.error(helpActionErrorMessage(e));
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myHelpAcceptancesProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        leading: const AppBackButton(),
        title: const Text('Trabalho como ajudante'),
      ),
      body: SafeArea(
        top: false,
        child: switch (async) {
          AsyncValue(:final value?) => _content(value),
          AsyncValue(:final error?) => _HelperJobMessage(
              icon: Icons.cloud_off_outlined,
              message: friendlyError(error),
              actionLabel: 'Tentar novamente',
              onAction: () => ref.invalidate(myHelpAcceptancesProvider),
            ),
          _ => const _HelperJobLoading(),
        },
      ),
    );
  }

  Widget _content(List<HelpAcceptanceSummary> acceptances) {
    final acceptance =
        acceptances.where((a) => a.id == widget.acceptanceId).firstOrNull;
    if (acceptance == null) {
      return _HelperJobMessage(
        icon: Icons.search_off_rounded,
        message: 'Não encontrámos esta candidatura. Pode ter sido removida.',
        actionLabel: 'Ver as minhas candidaturas',
        onAction: () => context.go(
          '/worker/help-requests',
          extra: const {'initialTabIndex': 1},
        ),
      );
    }

    final stage = helperJobStage(acceptance.status, acceptance.jobStatus);
    final actions = helperJobActions(acceptance);
    var index = 0;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          AppStaggeredEntrance(
            index: index++,
            child: _HeaderRow(acceptance: acceptance, stage: stage),
          ),
          const SizedBox(height: AppSpacing.md),
          AppStaggeredEntrance(
            index: index++,
            // Mesmo stepper da cliente e do responsável (A12); a candidatura
            // fechada fica com o timeline, que diz porquê.
            child: helperJobFlowStage(stage) == null
                ? _TimelineCard(
                    steps: helperTimelineSteps(acceptance, stage),
                    closed: true,
                  )
                : _FlowCard(
                    stage: helperJobFlowStage(stage)!,
                    message: _stageSubtitle(stage, acceptance),
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppStaggeredEntrance(
            index: index++,
            child: _DetailsCard(acceptance: acceptance, actions: actions),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppStaggeredEntrance(
            index: index++,
            child: _PrincipalCard(acceptance: acceptance, actions: actions),
          ),
          if (actions.canRatePrincipal) ...[
            const SizedBox(height: AppSpacing.sm),
            AppStaggeredEntrance(
              index: index++,
              child: _RatePrincipalSection(acceptance: acceptance),
            ),
          ],
          if (actions.giveUpClosedByJobDay) ...[
            const SizedBox(height: AppSpacing.md),
            AppStaggeredEntrance(
              index: index++,
              child: Text(
                helperGiveUpClosedMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
          if (actions.canWithdrawApplication || actions.canGiveUp) ...[
            const SizedBox(height: AppSpacing.md),
            AppStaggeredEntrance(
              index: index++,
              child: Center(
                child: TextButton(
                  onPressed: _withdrawing ? null : () => _withdraw(acceptance),
                  style: TextButton.styleFrom(
                    foregroundColor: AppStatusColor.cancelled.foreground,
                    textStyle: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  child: Text(
                    _withdrawing
                        ? (actions.canWithdrawApplication
                            ? 'A retirar...'
                            : 'A desistir...')
                        : (actions.canWithdrawApplication
                            ? 'Retirar candidatura'
                            : 'Desistir'),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Etiqueta e cor do estado atual da candidatura.
AppStatusPresentation helperStagePresentation(
  HelpAcceptanceSummary acceptance,
  HelperJobStage stage,
) {
  return switch (stage) {
    HelperJobStage.pending => const AppStatusPresentation(
        label: 'Candidatura pendente',
        color: AppStatusColor.waiting,
      ),
    HelperJobStage.accepted => const AppStatusPresentation(
        label: 'Aceite',
        color: AppStatusColor.success,
      ),
    HelperJobStage.workDone => const AppStatusPresentation(
        label: 'Trabalho feito',
        color: AppStatusColor.info,
      ),
    HelperJobStage.completed => const AppStatusPresentation(
        label: 'Concluído',
        color: AppStatusColor.success,
      ),
    HelperJobStage.closed => AppStatusPresentation(
        label: helperClosedLabel(acceptance.status, acceptance.jobStatus),
        color: AppStatusColor.cancelled,
      ),
  };
}

/// Passos da timeline: candidatura → aceite → trabalho feito → concluído.
/// Numa candidatura fechada: candidatura → motivo do fecho.
@visibleForTesting
List<StatusTimelineStepData> helperTimelineSteps(
  HelpAcceptanceSummary acceptance,
  HelperJobStage stage,
) {
  if (stage == HelperJobStage.closed) {
    return [
      const StatusTimelineStepData(
        label: 'Candidatura',
        statusColor: AppStatusColor.success,
        state: StatusTimelineStepState.completed,
      ),
      StatusTimelineStepData(
        label: helperClosedLabel(acceptance.status, acceptance.jobStatus),
        statusColor: AppStatusColor.cancelled,
        state: StatusTimelineStepState.current,
        subtitle: _closedSubtitle(acceptance),
      ),
    ];
  }

  const order = [
    HelperJobStage.pending,
    HelperJobStage.accepted,
    HelperJobStage.workDone,
    HelperJobStage.completed,
  ];
  const labels = ['Candidatura', 'Aceite', 'Trabalho feito', 'Concluído'];
  final currentIndex = order.indexOf(stage);
  final current = helperStagePresentation(acceptance, stage);
  return [
    for (var i = 0; i < order.length; i++)
      StatusTimelineStepData(
        label: labels[i],
        statusColor: i < currentIndex
            ? AppStatusColor.success
            : (i == currentIndex ? current.color : AppStatusColor.neutral),
        state: i < currentIndex
            ? StatusTimelineStepState.completed
            : (i == currentIndex
                ? StatusTimelineStepState.current
                : StatusTimelineStepState.future),
        subtitle: i == currentIndex ? _stageSubtitle(stage, acceptance) : null,
      ),
  ];
}

String _stageSubtitle(HelperJobStage stage, HelpAcceptanceSummary a) =>
    switch (stage) {
      HelperJobStage.pending =>
        'À espera da decisão de ${_principal(a)}.',
      HelperJobStage.accepted => 'Estás na equipa. Combina os detalhes por WhatsApp.',
      HelperJobStage.workDone =>
        'O responsável marcou o trabalho como feito. Falta o cliente confirmar.',
      HelperJobStage.completed => 'Trabalho concluído. Obrigado pela ajuda!',
      HelperJobStage.closed => '',
    };

String? _closedSubtitle(HelpAcceptanceSummary a) {
  if (a.jobStatus == JobStatus.cancelled.value) {
    return 'O trabalho foi cancelado.';
  }
  if (a.jobStatus == JobStatus.noResponse.value) return 'O pedido expirou.';
  return switch (a.status) {
    HelpAcceptanceStatus.rejected =>
      '${_principal(a)} escolheu outros ajudantes.',
    HelpAcceptanceStatus.cancelled =>
      'Esta candidatura já não está ativa.',
    _ => null,
  };
}

String _principal(HelpAcceptanceSummary a) =>
    a.principalName.trim().isEmpty || a.principalName == '—'
        ? 'o jardineiro responsável'
        : a.principalName;

/// "Sábado, 25/10 · 8:30" (sem hora: só o dia).
String _scheduleLabel(DateTime date, String? time) {
  final day = weekdayDateLabel(date);
  if (time == null || time.length < 5) return day;
  final hour = int.tryParse(time.substring(0, 2));
  final clock = hour == null ? time.substring(0, 5) : '$hour${time.substring(2, 5)}';
  return '$day · $clock';
}

/// Valor a mostrar: acordado depois de aceite; enquanto pendente, a
/// sugestão do pedido de ajuda (`payment_per_helper`, 0049).
@visibleForTesting
String helperRateLabel(HelpAcceptanceSummary a) {
  if (a.status == HelpAcceptanceStatus.accepted && a.agreedRate > 0) {
    return '${hourlyRateLabel(a.agreedRate)} acordado';
  }
  final offered = a.paymentPerHelper;
  if (a.status == HelpAcceptanceStatus.pending && offered != null && offered > 0) {
    return 'Sugestão: ${hourlyRateLabel(offered)}';
  }
  return 'Valor a combinar';
}

/// "Ajudas Miguel", o serviço e o estado, sem cartão (design U4).
/// Stepper do fluxo e o que se passa agora, no lugar do timeline.
class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.stage, required this.message});

  final JobFlowStage stage;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          JobFlowStepper(stage: stage),
          if (message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                0,
              ),
              child: Text(
                message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.acceptance, required this.stage});

  final HelpAcceptanceSummary acceptance;
  final HelperJobStage stage;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: AppSizes.actionIconBox,
          height: AppSizes.actionIconBox,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          child: const Icon(Icons.handshake_outlined, color: AppColors.primary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ajudas ${_principal(acceptance)}',
                style:
                    textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
              ),
              Text(
                acceptance.serviceTypeName,
                style: textTheme.labelMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        AppStatusBadge.fromPresentation(
          presentation: helperStagePresentation(acceptance, stage),
          dense: true,
        ),
      ],
    );
  }
}

/// Timeline horizontal e, por baixo, a frase do passo atual numa caixa
/// verde (vermelha quando a candidatura fechou).
class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.steps, required this.closed});

  final List<StatusTimelineStepData> steps;
  final bool closed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final message = steps
        .where((s) => s.state == StatusTimelineStepState.current)
        .map((s) => s.subtitle)
        .firstOrNull;
    final background =
        closed ? AppStatusColor.cancelled.background : AppColors.primaryTint;
    final foreground =
        closed ? AppStatusColor.cancelled.foreground : AppColors.primary;
    return _SectionCard(
      child: Column(
        children: [
          // A frase do passo vai na caixa de baixo, não por baixo do traço.
          StatusTimelineHorizontal(
            steps: [
              for (final step in steps)
                StatusTimelineStepData(
                  label: step.label,
                  statusColor: step.statusColor,
                  state: step.state,
                  dateLabel: step.dateLabel,
                  note: step.note,
                  noteIsWarning: step.noteIsWarning,
                ),
            ],
          ),
          if (message != null && message.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Text(
                message,
                style: textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Data, valor, equipamento e morada em linhas "rótulo · valor".
class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.acceptance, required this.actions});

  final HelpAcceptanceSummary acceptance;
  final HelperJobActions actions;

  @override
  Widget build(BuildContext context) {
    final hasCoordinates =
        acceptance.locationLat != 0 || acceptance.locationLng != 0;
    final isPending =
        helperJobStage(acceptance.status, acceptance.jobStatus) ==
            HelperJobStage.pending;
    final String? address;
    if (actions.showsContact) {
      address = acceptance.addressText.isNotEmpty
          ? acceptance.addressText
          : (hasCoordinates ? 'Localização no mapa' : null);
    } else if (isPending) {
      address = acceptance.addressText.isNotEmpty
          ? acceptance.addressText
          : 'A morada exata aparece quando fores aceite.';
    } else {
      address = null;
    }

    return _SectionCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
      child: Column(
        children: [
          _FactRow(
            icon: Icons.event_outlined,
            label: 'Data',
            value: acceptance.confirmedDate != null
                ? _scheduleLabel(
                    acceptance.confirmedDate!, acceptance.confirmedTime)
                : 'A combinar',
          ),
          const Divider(height: 1, color: AppColors.divider),
          _FactRow(
            icon: Icons.payments_outlined,
            label: 'Valor',
            value: helperRateLabel(acceptance),
          ),
          const Divider(height: 1, color: AppColors.divider),
          _FactRow(
            icon: Icons.handyman_outlined,
            label: 'Equipamento',
            value: acceptance.broughtEquipment
                ? 'Levas equipamento'
                : 'Sem equipamento',
          ),
          if (address != null) ...[
            const Divider(height: 1, color: AppColors.divider),
            _FactRow(
              icon: Icons.place_outlined,
              value: address,
              trailing: actions.showsContact && hasCoordinates
                  ? TextButton(
                      onPressed: () => AddressMapLink.openInMaps(
                        acceptance.locationLat,
                        acceptance.locationLng,
                      ),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.only(left: AppSpacing.sm),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Mapa'),
                    )
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// Uma linha do cartão de detalhes: ícone, rótulo à esquerda e valor em
/// negrito à direita. Sem [label], o valor ocupa a linha (morada).
class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.icon,
    required this.value,
    this.label,
    this.trailing,
  });

  final IconData icon;
  final String? label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final valueStyle = textTheme.bodyMedium?.copyWith(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w700,
    );
    final rowLabel = label;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: AppSizes.rowIcon, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          if (rowLabel != null) ...[
            Text(
              rowLabel,
              style:
                  textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(value, textAlign: TextAlign.right, style: valueStyle),
            ),
          ] else
            Expanded(child: Text(value, style: valueStyle)),
          ?trailing,
        ],
      ),
    );
  }
}

class _PrincipalCard extends ConsumerWidget {
  const _PrincipalCard({required this.acceptance, required this.actions});

  final HelpAcceptanceSummary acceptance;
  final HelperJobActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final principalId = acceptance.principalWorkerId;
    final summary = principalId.isNotEmpty
        ? ref.watch(ratingSummaryProvider(principalId)).asData?.value
        : null;
    final hasRating = summary != null && summary.ratingCount > 0;
    final phone = acceptance.principalPhone;
    final name = _principal(acceptance);

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: AppSizes.rowIconBox / 2,
                backgroundColor: AppColors.primaryContainer,
                child: Text(
                  name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
                  style:
                      textTheme.titleMedium?.copyWith(color: AppColors.primary),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RESPONSÁVEL',
                      style: textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    InkWell(
                      onTap: hasRating
                          ? () => showWorkerRatingsSheet(
                                context,
                                workerId: principalId,
                                workerName: acceptance.principalName,
                              )
                          : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: textTheme.titleMedium?.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (hasRating) ...[
                            const SizedBox(width: AppSpacing.xxs),
                            Icon(
                              Icons.star_rounded,
                              size: AppSizes.inlineIcon,
                              color: AppStatusColor.waiting.foreground,
                            ),
                            Text(
                              decimalLabel(summary.avgRating, 1),
                              style: textTheme.titleSmall?.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (actions.showsContact && phone.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            AppWhatsAppButton(
              onPressed: () => openWhatsAppOrWarn(context, phone),
            ),
          ] else if (!actions.showsContact) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'O contacto aparece quando fores aceite na equipa.',
              style:
                  textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _RatePrincipalSection extends ConsumerWidget {
  const _RatePrincipalSection({required this.acceptance});

  final HelpAcceptanceSummary acceptance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final ratingAsync = ref.watch(myRatingForJobProvider(acceptance.jobId));
    return AppFadeThroughSwitcher(
      switchKey: ratingAsync.asData?.value?.id ?? ratingAsync.isLoading,
      child: ratingAsync.when(
        loading: () => AppSkeletonShimmer(
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
          ),
        ),
        error: (_, _) => const SizedBox.shrink(),
        data: (existing) {
          if (existing != null) {
            return _SectionCard(
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Responsável avaliado',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                  for (var i = 0; i < 5; i++)
                    Icon(
                      i < existing.stars
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: AppStatusColor.waiting.foreground,
                    ),
                ],
              ),
            );
          }
          return SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: () => showRatePrincipalSheet(context, ref, acceptance),
              child: const Text('Avaliar o responsável'),
            ),
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: child,
    );
  }
}

class _HelperJobLoading extends StatelessWidget {
  const _HelperJobLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        for (final height in const [96.0, 120.0, 140.0, 110.0]) ...[
          AppSkeletonShimmer(
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _HelperJobMessage extends StatelessWidget {
  const _HelperJobMessage({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textSecondary),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
