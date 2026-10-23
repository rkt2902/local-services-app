import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_back_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_utils.dart';
import '../../proposals/application/proposal_price_labels.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';
import '../../ratings/application/rating_providers.dart';
import '../../ratings/presentation/worker_ratings_sheet.dart';
import '../application/client_proposal_labels.dart';
import '../application/job_providers.dart';
import 'widgets/client_proposal_detail_view.dart';

/// Detalhe de uma proposta recebida e "Aceitar por ..." (design A6, D).
/// Lê a mesma lista de "Propostas recebidas" (sem pedido novo); a
/// validade vem do servidor e `accept_proposal` volta a validar.
class ClientProposalDetailScreen extends ConsumerWidget {
  const ClientProposalDetailScreen({
    super.key,
    required this.jobId,
    required this.proposalId,
  });

  final String jobId;
  final String proposalId;

  /// Lembretes fixos da aceitação (regras atuais do produto). A app não
  /// trata pagamentos: o cliente paga diretamente ao jardineiro.
  static const _infoLines = [
    ClientProposalInfoLine(
      icon: Icons.notifications_active_outlined,
      label: 'O jardineiro recebe a confirmação e as outras propostas são '
          'fechadas.',
    ),
    ClientProposalInfoLine(
      icon: Icons.event_repeat_outlined,
      label: 'Podes remarcar ou cancelar até à véspera do trabalho.',
    ),
    ClientProposalInfoLine(
      icon: Icons.payments_outlined,
      label: 'Pagas diretamente ao jardineiro, depois de confirmares que o '
          'trabalho está feito.',
    ),
  ];

  Future<ClientProposalAcceptResult> _accept(WidgetRef ref) async {
    try {
      await ref
          .read(proposalRepositoryProvider)
          .acceptProposal(proposalId, jobId);
      return const ClientProposalAcceptResult.accepted();
    } catch (e) {
      // accept_proposal e o trigger da 0058 só devolvem texto, sem
      // ERRCODE próprio (mesma convenção de createProposal).
      final msg = e.toString();
      if (msg.contains('expirou')) {
        ref.invalidate(pendingProposalsForJobProvider(jobId));
        return const ClientProposalAcceptResult.expired();
      }
      if (msg.contains('já não está disponível') ||
          msg.contains('já processada') ||
          msg.contains('não encontrada')) {
        ref.invalidate(pendingProposalsForJobProvider(jobId));
        return const ClientProposalAcceptResult.unavailable();
      }
      return ClientProposalAcceptResult.failed(friendlyError(e));
    }
  }

  void _onAccepted(BuildContext context, WidgetRef ref, String workerId) {
    // `go`: o detalhe do pedido e a lista ficariam presos por baixo da
    // confirmação.
    GoRouter.of(context).go(
      '/client/job/$jobId/confirmed?workerId=$workerId',
    );
    // T4: invalidar só depois de navegar.
    ref.invalidate(clientJobsProvider);
    ref.invalidate(pendingProposalsForJobProvider(jobId));
    ref.invalidate(jobByIdProvider(jobId));
    // O detalhe do pedido aberto já leu "sem proposta aceite" (null) e a
    // cache guardava-o: a confirmação mostrava o preço como "—".
    ref.invalidate(acceptedProposalForJobProvider(jobId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proposalsAsync = ref.watch(pendingProposalsForJobProvider(jobId));
    final includeOptions =
        ref.watch(proposalIncludeOptionsProvider).asData?.value ?? const [];

    final proposal = proposalsAsync.asData?.value
        .where((p) => p.id == proposalId)
        .firstOrNull;
    final summary = proposal == null
        ? null
        : ref.watch(ratingSummaryProvider(proposal.workerId)).asData?.value;

    final dataAsync = proposalsAsync.whenData(
      (_) => proposal == null
          ? null
          : _viewData(proposal, summary, includeOptions),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: ClientProposalDetailView(
          dataAsync: dataAsync,
          onBack: () => goBackOr(context, '/client/job/$jobId/proposals'),
          onRetry: () => ref.invalidate(pendingProposalsForJobProvider(jobId)),
          onBackToList: () => goBackOr(context, '/client/job/$jobId/proposals'),
          onOpenWorkerProfile: () {
            if (proposal == null) return;
            showWorkerRatingsSheet(
              context,
              workerId: proposal.workerId,
              workerName: proposal.workerName ?? 'Jardineiro',
            );
          },
          onAccept: (_) => _accept(ref),
          onAccepted: () =>
              _onAccepted(context, ref, proposal?.workerId ?? ''),
        ),
      ),
    );
  }

  ClientProposalDetailViewData _viewData(
    JobProposal p,
    RatingSummary? summary,
    List<ProposalIncludeOption> includeOptions,
  ) {
    final name =
        p.workerName?.isNotEmpty == true ? p.workerName! : 'Jardineiro';
    final duration = proposalDurationLabel(p);
    final validUntil = proposalValidUntilLabel(p);
    final helpers = p.peopleNeeded - 1;
    final total = proposalTotalLabel(p);
    final value = proposalValueLabel(p);
    return ClientProposalDetailViewData(
      proposalId: p.id,
      workerId: p.workerId,
      workerName: name,
      workerAvatarUrl: p.workerAvatarUrl,
      ratingLabel: proposalRatingLabel(summary),
      priceTitle: p.isFixedTotal ? 'Valor fechado' : 'Preço por hora',
      priceLabel: value,
      priceExplanationLabel: proposalPriceExplanationLabel(p),
      totalLabel: p.isFixedTotal || total == null
          ? null
          : 'Total estimado: $total',
      includeLabels: proposalIncludeLabels(p, includeOptions),
      notes: p.notes,
      facts: [
        ClientProposalFact(
          'Início',
          p.scheduledDate == null
              ? 'A combinar'
              : proposalScheduleLabel(p),
        ),
        if (duration.isNotEmpty) ClientProposalFact('Duração', duration),
        if (helpers > 0) ClientProposalFact('Ajudantes', '$helpers'),
        if (validUntil != null)
          ClientProposalFact(
            'Válido até',
            validUntil.replaceFirst('Válido até ', ''),
          ),
      ],
      infoLines: _infoLines,
      acceptActionLabel: 'Aceitar por $value',
      expiringSoonLabel:
          proposalExpiringSoonLabel(p, now: DateTime.now()),
      expired: p.isExpired,
      expiredTitle: proposalExpiredLabel(p),
    );
  }
}
