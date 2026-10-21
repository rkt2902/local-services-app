import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/router/app_back_navigation.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/price_labels.dart';
import '../../jobs/application/job_labels.dart';
import '../../jobs/application/job_providers.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';
import '../../ratings/application/rating_providers.dart';
import '../../ratings/presentation/worker_ratings_sheet.dart';
import '../../worker/application/worker_providers.dart';
import '../application/help_request_providers.dart';
import '../application/helper_job_state.dart';
import '../data/help_request_model.dart';
import 'widgets/worker_help_requests_lobby_view.dart';

/// "Equipa" — lobby de ajudantes do worker responsável por um job.
///
/// Wrapper que liga os providers reais ao componente apresentacional em
/// widgets/worker_help_requests_lobby_view.dart — este ficheiro é o único
/// que fala com Supabase; o widget de apresentação não sabe que Riverpod
/// existe.
///
/// Navegação: aberto pelo cartão "Equipa" do ecrã "O meu trabalho"
/// ([fromMyJob] = true) ou por 2 notificações (`helpRequestApproved`,
/// `helpWithdrew`). O estado vazio ("Pedir ajudantes") volta ao ecrã do
/// trabalho, que é onde vive a sheet de pedir ajudantes.
class WorkerHelpRequestsLobbyScreen extends ConsumerStatefulWidget {
  const WorkerHelpRequestsLobbyScreen({
    super.key,
    required this.jobId,
    this.fromMyJob = false,
  });

  final String jobId;

  /// `true` quando o ecrã anterior na stack é o "O meu trabalho" deste
  /// pedido: aí basta um pop para lá voltar.
  final bool fromMyJob;

  @override
  ConsumerState<WorkerHelpRequestsLobbyScreen> createState() =>
      _WorkerHelpRequestsLobbyScreenState();
}

class _WorkerHelpRequestsLobbyScreenState
    extends ConsumerState<WorkerHelpRequestsLobbyScreen> {
  double _suggestedRate(
      HelpRequest hr, HelpAcceptance candidate, JobProposal? proposal) {
    final rate = proposal?.hourlyRate ?? 0;
    if (hr.equipmentRequired) return rate;
    return candidate.broughtEquipment ? rate : rate * 0.7;
  }

  /// `null` quando a proposta não tem horas estimadas (o ecrã não inventa
  /// uma duração — ver instrução original).
  String? _estimateLabel(JobProposal? proposal, double rate) {
    final min = proposal?.estimatedHoursMin;
    if (min == null) return null;
    final max = proposal?.estimatedHoursMax;
    final minTotal = rate * min;
    if (max == null) {
      return '≈ ${_hours(min)} h estimadas · total aproximado a partir de '
          '${moneyLabel(minTotal)}';
    }
    final maxTotal = rate * max;
    return '≈ ${_hours(min)} a ${_hours(max)} h estimadas · total aproximado '
        '${decimalLabel(minTotal, 2)} a ${moneyLabel(maxTotal)}';
  }

  String _hours(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : decimalLabel(value, 1);

  Future<bool> _acceptCandidate(String helpAcceptanceId, String rateInput) async {
    final parsed = double.tryParse(rateInput.replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) return false;
    try {
      await ref.read(helpRequestRepositoryProvider).acceptCandidate(
            helpAcceptanceId: helpAcceptanceId,
            agreedRate: parsed,
          );
      _invalidateAfterAction();
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppStatusColor.cancelled.foreground),
        );
      }
      return false;
    }
  }

  Future<bool> _rejectCandidate(String helpAcceptanceId) async {
    try {
      await ref.read(helpRequestRepositoryProvider).rejectHelpCandidate(helpAcceptanceId);
      _invalidateAfterAction();
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppStatusColor.cancelled.foreground),
        );
      }
      return false;
    }
  }

  void _invalidateAfterAction() {
    final helpRequests = ref.read(helpRequestsForJobProvider(widget.jobId)).value ?? [];
    ref.invalidate(helpRequestsForJobProvider(widget.jobId));
    for (final hr in helpRequests) {
      ref.invalidate(candidatesForHelpRequestProvider(hr.id));
    }
  }

  /// Ações de gestão da equipa (0049). Sem navegação: o feedback de
  /// sucesso é da view; aqui só o erro (SnackBar) e a invalidação (T4).
  Future<bool> _runTeamAction(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return true;
      _invalidateAfterAction();
      // A vaga reaberta/fechada muda a descoberta de pedidos de ajuda.
      ref.invalidate(helpRequestSummariesInRadiusProvider);
      ref.invalidate(acceptedHelpersForJobProvider(widget.jobId));
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(helpActionErrorMessage(e)),
            backgroundColor: AppStatusColor.cancelled.foreground,
          ),
        );
      }
      return false;
    }
  }

  Future<bool> _changeSlots(String helpRequestId, int slots) => _runTeamAction(
        () => ref.read(helpRequestRepositoryProvider).updateHelpRequestSlots(
              helpRequestId: helpRequestId,
              slots: slots,
            ),
      );

  Future<bool> _closeHelpRequest(String helpRequestId) => _runTeamAction(
        () => ref
            .read(helpRequestRepositoryProvider)
            .cancelHelpRequest(helpRequestId),
      );

  Future<bool> _removeHelper(String helpAcceptanceId) => _runTeamAction(
        () => ref
            .read(helpRequestRepositoryProvider)
            .removeHelpHelper(helpAcceptanceId),
      );

  String? _rateValidator(String? value) {
    final parsed = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) return 'A taxa deve ser maior que zero.';
    return null;
  }

  /// Serviço, zona e data em vez do id do pedido ("Poda · Braga · 18/10").
  String _jobReferenceLabel() {
    final job = ref.watch(jobByIdProvider(widget.jobId)).asData?.value;
    if (job == null) return 'Trabalho';
    final service = ref
            .watch(serviceTypesProvider)
            .asData
            ?.value
            .where((s) => s.id == job.serviceTypeId)
            .map((s) => s.name)
            .firstOrNull ??
        'Trabalho';
    return '$service · ${jobDistinguisherLabel(job)}';
  }

  /// "Pedir ajudantes" no estado vazio: a sheet vive no ecrã do trabalho.
  /// Veio de lá → pop. Senão (notificação) → substitui este ecrã pelo do
  /// trabalho, sem duplicar a stack. Sem proposta conhecida → voltar.
  void _goToJobToRequestHelpers(JobProposal? proposal) {
    if (widget.fromMyJob && context.canPop()) {
      context.pop();
      return;
    }
    if (proposal != null) {
      context.pushReplacement(
        '/worker/my-job/${proposal.id}?jobId=${widget.jobId}',
        extra: const {'entryTransition': 'sharedAxis'},
      );
      return;
    }
    goBackOrToRoleHome(context);
  }

  void _viewRatings(String workerId, String name) {
    showWorkerRatingsSheet(context, workerId: workerId, workerName: name);
  }

  @override
  Widget build(BuildContext context) {
    final workerAsync = ref.watch(workerProfileProvider);
    final proposalAsync = ref.watch(acceptedProposalForJobProvider(widget.jobId));
    final proposal = proposalAsync.asData?.value;
    final helpRequestsAsync = ref.watch(helpRequestsForJobProvider(widget.jobId));
    final helpRequests = helpRequestsAsync.asData?.value ?? [];

    var anyLoading = helpRequestsAsync.isLoading;
    Object? anyError = helpRequestsAsync.hasError ? helpRequestsAsync.error : null;
    StackTrace? anyStack = helpRequestsAsync.hasError ? helpRequestsAsync.stackTrace : null;

    final candidatesByHr = <String, List<HelpAcceptance>>{};
    for (final hr in helpRequests) {
      final cAsync = ref.watch(candidatesForHelpRequestProvider(hr.id));
      if (cAsync.isLoading) anyLoading = true;
      if (cAsync.hasError) {
        anyError ??= cAsync.error;
        anyStack ??= cAsync.stackTrace;
      }
      candidatesByHr[hr.id] = cAsync.asData?.value ?? [];
    }

    final AsyncValue<WorkerHelpLobbyViewData> dataAsync;
    if (anyLoading) {
      dataAsync = const AsyncValue.loading();
    } else if (anyError != null) {
      dataAsync = AsyncValue.error(anyError, anyStack ?? StackTrace.current);
    } else {
      final workerProfile = workerAsync.asData?.value;
      final jobStatus = ref.watch(jobByIdProvider(widget.jobId)).asData?.value?.status;
      // Só se mexe na equipa enquanto o trabalho está por fazer.
      final jobAllowsTeamChanges =
          jobStatus == JobStatus.open || jobStatus == JobStatus.confirmed;

      final sections = <HelpRequestSectionViewData>[];
      for (final hr in helpRequests) {
        final all = List<HelpAcceptance>.from(candidatesByHr[hr.id] ?? [])
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final accepted =
            all.where((c) => c.status == HelpAcceptanceStatus.accepted).toList();
        final pending =
            all.where((c) => c.status == HelpAcceptanceStatus.pending).toList();
        // Guarda defensiva: se accepted_count >= slots_needed o backend
        // (migration 0017) já auto-rejeitou os pending restantes. Evita
        // mostrar "Aceitar" acionável na janela breve antes do refetch.
        final isFilled = accepted.length >= hr.slotsNeeded;
        final isAwaitingApproval = hr.status == HelpRequestStatus.pendingApproval;

        sections.add(HelpRequestSectionViewData(
          helpRequestId: hr.id,
          slotsNeeded: hr.slotsNeeded,
          canManage: jobAllowsTeamChanges &&
              hr.status != HelpRequestStatus.cancelled,
          displayMode: isAwaitingApproval
              ? WorkerHelpSectionDisplayMode.awaitingClientApproval
              : (isFilled
                  ? WorkerHelpSectionDisplayMode.filled
                  : WorkerHelpSectionDisplayMode.active),
          statusPresentation: hr.status.presentation,
          filledPlacesLabel:
              '${accepted.length} de ${hr.slotsNeeded} vaga${hr.slotsNeeded == 1 ? '' : 's'} '
              'preenchida${hr.slotsNeeded == 1 ? '' : 's'}',
          filledCountLabel: '${accepted.length} de ${hr.slotsNeeded}',
          filledProgress: hr.slotsNeeded == 0 ? 0 : accepted.length / hr.slotsNeeded,
          acceptedHelpers: accepted
              .map((c) => WorkerAcceptedHelperViewData(
                    applicationId: c.id,
                    workerId: c.workerId,
                    name: c.fullName ?? 'Sem nome',
                    avatarUrl: c.avatarUrl,
                    ratingLabel: _ratingLabelFor(c.workerId),
                    equipmentLabel:
                        c.broughtEquipment ? 'Traz equipamento' : 'Sem equipamento',
                    rateLabel:
                        c.agreedRate > 0 ? hourlyRateLabel(c.agreedRate) : null,
                    statusPresentation: c.status.presentation,
                    phone: c.workerPhone,
                  ))
              .toList(),
          pendingCandidates: pending.map((c) {
            final suggested = _suggestedRate(hr, c, proposal);
            return WorkerHelpCandidateViewData(
              applicationId: c.id,
              workerId: c.workerId,
              name: c.fullName ?? 'Sem nome',
              avatarUrl: c.avatarUrl,
              ratingLabel: _ratingLabelFor(c.workerId),
              equipmentLabel: c.broughtEquipment ? 'Traz equipamento' : 'Sem equipamento',
              message: c.message,
              statusPresentation: c.status.presentation,
              actionsBlocked: isFilled || isAwaitingApproval,
              blockedReasonLabel: isFilled
                  ? 'Vagas já preenchidas.'
                  : (isAwaitingApproval ? 'À espera de aprovação do cliente.' : null),
              acceptance: AcceptHelperViewData(
                initialRateInput: decimalLabel(suggested, 2),
                suggestedRateLabel: 'Sugerido: ${hourlyRateLabel(suggested)}',
                estimateLabel: _estimateLabel(proposal, suggested),
              ),
            );
          }).toList(),
        ));
      }

      dataAsync = AsyncValue.data(WorkerHelpLobbyViewData(
        jobReferenceLabel: _jobReferenceLabel(),
        responsibleName: workerProfile?.fullName ?? '',
        responsibleAvatarUrl: workerProfile?.avatarUrl,
        sections: sections,
      ));
    }

    return WorkerHelpRequestsLobbyView(
      dataAsync: dataAsync,
      onBack: () => goBackOrToRoleHome(context),
      onRequestHelpers: () => _goToJobToRequestHelpers(proposal),
      onAcceptCandidate: _acceptCandidate,
      onRejectCandidate: _rejectCandidate,
      onViewRatings: _viewRatings,
      rateValidator: _rateValidator,
      onChangeSlots: _changeSlots,
      onCloseHelpRequest: _closeHelpRequest,
      onRemoveHelper: _removeHelper,
      onRetry: () {
        ref.invalidate(helpRequestsForJobProvider(widget.jobId));
        for (final hr in helpRequests) {
          ref.invalidate(candidatesForHelpRequestProvider(hr.id));
        }
      },
    );
  }

  String? _ratingLabelFor(String workerId) {
    final summary = ref.watch(ratingSummaryProvider(workerId)).asData?.value;
    if (summary == null || summary.ratingCount == 0) return null;
    return decimalLabel(summary.avgRating, 1);
  }
}
