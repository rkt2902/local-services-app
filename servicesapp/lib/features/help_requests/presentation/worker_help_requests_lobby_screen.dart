import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/error_utils.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';
import '../../ratings/application/rating_providers.dart';
import '../../ratings/presentation/ratings_sheet.dart';
import '../../worker/application/worker_providers.dart';
import '../application/help_request_providers.dart';
import '../data/help_request_model.dart';
import 'widgets/worker_help_requests_lobby_view.dart';

/// "Equipa" — lobby de ajudantes do worker responsável por um job.
///
/// Wrapper que liga os providers reais ao componente apresentacional em
/// widgets/worker_help_requests_lobby_view.dart — este ficheiro é o único
/// que fala com Supabase; o widget de apresentação não sabe que Riverpod
/// existe.
///
/// Nota de navegação (2026-09): confirmado que hoje este ecrã só é
/// alcançável a partir de 2 tipos de notificação (`helpRequestApproved`,
/// `helpWithdrew`) — ambos só disparam quando já existe um `HelpRequest`
/// para o job. Não há nenhum botão em nenhum outro ecrã que abra este
/// lobby diretamente. Isto significa que o estado vazio ("Sem vagas neste
/// trabalho") é hoje inalcançável através da navegação normal da app —
/// mantido por robustez (ex.: um deep link futuro, ou se o worker chegar
/// aqui e o único `HelpRequest` for cancelado entretanto), não porque haja
/// um caminho real que o produza agora.
class WorkerHelpRequestsLobbyScreen extends ConsumerStatefulWidget {
  const WorkerHelpRequestsLobbyScreen({
    super.key,
    required this.jobId,
  });

  final String jobId;

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
      return '≈ ${_hours(min)}h estimadas · total aproximado a partir de '
          '€${minTotal.toStringAsFixed(2)}';
    }
    final maxTotal = rate * max;
    return '≈ ${_hours(min)}–${_hours(max)}h estimadas · total aproximado '
        '€${minTotal.toStringAsFixed(2)}–€${maxTotal.toStringAsFixed(2)}';
  }

  String _hours(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString();

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
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
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
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
      return false;
    }
  }

  void _invalidateAfterAction() {
    ref.invalidate(helpRequestsForJobProvider(widget.jobId));
    final helpRequests = ref.read(helpRequestsForJobProvider(widget.jobId)).value ?? [];
    for (final hr in helpRequests) {
      ref.invalidate(candidatesForHelpRequestProvider(hr.id));
    }
  }

  String? _rateValidator(String? value) {
    final parsed = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) return 'A taxa deve ser maior que zero.';
    return null;
  }

  void _viewRatings(String workerId, String name) {
    showRatingsSheet(context, workerId: workerId, workerName: name);
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
          displayMode: isAwaitingApproval
              ? WorkerHelpSectionDisplayMode.awaitingClientApproval
              : (isFilled
                  ? WorkerHelpSectionDisplayMode.filled
                  : WorkerHelpSectionDisplayMode.active),
          statusPresentation: hr.status.presentation,
          filledPlacesLabel:
              '${accepted.length} de ${hr.slotsNeeded} vaga${hr.slotsNeeded == 1 ? '' : 's'} '
              'preenchida${hr.slotsNeeded == 1 ? '' : 's'}',
          filledProgress: hr.slotsNeeded == 0 ? 0 : accepted.length / hr.slotsNeeded,
          acceptedHelpers: accepted
              .map((c) => WorkerAcceptedHelperViewData(
                    workerId: c.workerId,
                    name: c.fullName ?? 'Sem nome',
                    avatarUrl: c.avatarUrl,
                    ratingLabel: _ratingLabelFor(c.workerId),
                    equipmentLabel:
                        c.broughtEquipment ? 'Traz equipamento' : 'Sem equipamento',
                    rateLabel: c.agreedRate > 0
                        ? '€${c.agreedRate.toStringAsFixed(2)}/hora'
                        : null,
                    statusPresentation: c.status.presentation,
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
              statusPresentation: c.status.presentation,
              actionsBlocked: isFilled || isAwaitingApproval,
              blockedReasonLabel: isFilled
                  ? 'Vagas já preenchidas.'
                  : (isAwaitingApproval ? 'Aguarda aprovação do cliente.' : null),
              acceptance: AcceptHelperViewData(
                initialRateInput: suggested.toStringAsFixed(2),
                suggestedRateLabel: 'Sugerido: €${suggested.toStringAsFixed(2)}/hora',
                estimateLabel: _estimateLabel(proposal, suggested),
              ),
            );
          }).toList(),
        ));
      }

      dataAsync = AsyncValue.data(WorkerHelpLobbyViewData(
        jobReferenceLabel:
            'Job #${widget.jobId.length >= 8 ? widget.jobId.substring(0, 8) : widget.jobId}',
        responsibleName: workerProfile?.fullName ?? '',
        responsibleAvatarUrl: workerProfile?.avatarUrl,
        sections: sections,
      ));
    }

    return WorkerHelpRequestsLobbyView(
      dataAsync: dataAsync,
      onBack: () => context.pop(),
      onRequestHelpers: () => context.pop(),
      onAcceptCandidate: _acceptCandidate,
      onRejectCandidate: _rejectCandidate,
      onViewRatings: _viewRatings,
      rateValidator: _rateValidator,
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
    return summary.avgRating.toStringAsFixed(1);
  }
}
