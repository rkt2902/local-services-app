import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_back_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_utils.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';
import '../../ratings/application/rating_providers.dart';
import '../../ratings/presentation/worker_ratings_sheet.dart';
import '../application/client_proposal_labels.dart';
import '../application/job_providers.dart';
import 'widgets/client_proposals_view.dart';

/// "Propostas recebidas" de um pedido (design A3): lista única, já
/// ordenada por preço estimado, e a folha "Aceitar esta proposta?".
/// Liga os providers ao [ClientProposalsView], que só desenha.
class ClientProposalsScreen extends ConsumerWidget {
  const ClientProposalsScreen({super.key, required this.jobId});

  final String jobId;

  /// Textos fixos da folha de aceitação (regras atuais do produto). A app
  /// não trata pagamentos: o cliente paga diretamente ao jardineiro.
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

  Future<ClientProposalAcceptResult> _accept(
    WidgetRef ref,
    String proposalId,
  ) async {
    try {
      await ref
          .read(proposalRepositoryProvider)
          .acceptProposal(proposalId, jobId);
      return const ClientProposalAcceptResult.accepted();
    } catch (e) {
      // A RPC `accept_proposal` não devolve um ERRCODE dedicado para
      // "proposta já processada", só uma mensagem de texto (ver
      // migrations/0001_consolidated_baseline.sql). Mesma convenção de
      // classificação por texto de `proposal_repository.dart createProposal()`.
      final msg = e.toString();
      if (msg.contains('já não está disponível') ||
          msg.contains('já processada') ||
          msg.contains('não encontrada')) {
        ref.invalidate(pendingProposalsForJobProvider(jobId));
        return const ClientProposalAcceptResult.unavailable();
      }
      return ClientProposalAcceptResult.failed(friendlyError(e));
    }
  }

  void _onAccepted(
    BuildContext context,
    WidgetRef ref,
    ClientProposalCardViewData proposal,
  ) {
    // `go` (não `pushReplacement`): este ecrã chega por `push` a partir do
    // detalhe do pedido, que ficaria preso por baixo da confirmação.
    GoRouter.of(context).go(
      '/client/job/$jobId/confirmed?workerId=${proposal.workerId}',
    );
    // T4: invalidar só depois de navegar.
    ref.invalidate(clientJobsProvider);
    ref.invalidate(pendingProposalsForJobProvider(jobId));
    ref.invalidate(jobByIdProvider(jobId));
  }

  /// Voltar com fallback para o detalhe do pedido: num refresh da web ou
  /// link direto não há stack e `pop()` rebentava.
  void _back(BuildContext context) => goBackOr(context, '/client/job/$jobId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proposalsAsync = ref.watch(pendingProposalsForJobProvider(jobId));
    final job = ref.watch(jobByIdProvider(jobId)).asData?.value;
    final serviceTypes =
        ref.watch(serviceTypesProvider).asData?.value ?? const [];
    final serviceLabel = job == null
        ? null
        : serviceTypes
            .where((s) => s.id == job.serviceTypeId)
            .map((s) => s.name)
            .firstOrNull;

    final dataAsync = proposalsAsync.whenData((proposals) {
      final sorted = [...proposals]..sort(compareProposalsByEstimate);
      final summaries = {
        for (final p in sorted)
          p.workerId:
              ref.watch(ratingSummaryProvider(p.workerId)).asData?.value,
      };
      final recommendedId =
          recommendedProposalId(sorted, (id) => summaries[id]);
      return ClientProposalsViewData(
        headerSubtitle: proposalsHeaderSubtitle(serviceLabel, sorted.length),
        orderingLabel:
            'Ordenadas por preço estimado, da mais barata para a mais cara.',
        proposals: [
          for (final p in sorted)
            _cardData(p, summaries[p.workerId], p.id == recommendedId),
        ],
      );
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ClientProposalsView(
          dataAsync: dataAsync,
          onBack: () => _back(context),
          onRetry: () => ref.invalidate(pendingProposalsForJobProvider(jobId)),
          onOpenWorkerProfile: (p) => showWorkerRatingsSheet(
            context,
            workerId: p.workerId,
            workerName: p.workerName,
          ),
          onAcceptProposal: (id) => _accept(ref, id),
          onProposalAccepted: (p) => _onAccepted(context, ref, p),
        ),
      ),
    );
  }

  ClientProposalCardViewData _cardData(
    JobProposal p,
    RatingSummary? summary,
    bool recommended,
  ) {
    final name =
        p.workerName?.isNotEmpty == true ? p.workerName! : 'Jardineiro';
    final schedule = proposalScheduleLabel(p);
    final hours = proposalHoursLabel(p);
    final rateOrPrice = proposalPriceLabel(p);
    return ClientProposalCardViewData(
      proposalId: p.id,
      workerId: p.workerId,
      workerName: name,
      workerAvatarUrl: p.workerAvatarUrl,
      ratingLabel: proposalRatingLabel(summary),
      priceLabel: rateOrPrice,
      priceDetailLabel: proposalPriceDetailLabel(p),
      scheduleLabel: schedule,
      teamLabel: proposalTeamLabel(p),
      notes: p.notes,
      recommended: recommended,
      confirmation: ClientProposalConfirmationViewData(
        summaryMetaLabel: [
          if (p.scheduledDate != null) schedule,
          if (hours.isNotEmpty) hours,
        ].join(' · '),
        infoLines: _infoLines,
        confirmActionLabel: 'Aceitar proposta · $rateOrPrice',
      ),
    );
  }
}
