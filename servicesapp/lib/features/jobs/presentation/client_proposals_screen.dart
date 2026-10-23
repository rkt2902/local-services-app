import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_back_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../proposals/application/proposal_price_labels.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';
import '../../ratings/application/rating_providers.dart';
import '../application/client_proposal_labels.dart';
import '../application/job_providers.dart';
import 'widgets/client_proposals_view.dart';

/// "Propostas recebidas" de um pedido (designs A3 e A6): por hora e valor
/// total juntos, a recomendada primeiro e nunca ordenadas pelo preço.
/// Tocar num cartão abre o detalhe, onde se aceita.
class ClientProposalsScreen extends ConsumerWidget {
  const ClientProposalsScreen({super.key, required this.jobId});

  final String jobId;

  /// Voltar com fallback para o detalhe do pedido: num refresh da web ou
  /// link direto não há stack e `pop()` rebentava.
  void _back(BuildContext context) => goBackOr(context, '/client/job/$jobId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proposalsAsync = ref.watch(pendingProposalsForJobProvider(jobId));
    final job = ref.watch(jobByIdProvider(jobId)).asData?.value;
    final includeOptions =
        ref.watch(proposalIncludeOptionsProvider).asData?.value ?? const [];
    final serviceTypes =
        ref.watch(serviceTypesProvider).asData?.value ?? const [];
    final serviceLabel = job == null
        ? null
        : serviceTypes
            .where((s) => s.id == job.serviceTypeId)
            .map((s) => s.name)
            .firstOrNull;

    final dataAsync = proposalsAsync.whenData((proposals) {
      final summaries = {
        for (final p in proposals)
          p.workerId:
              ref.watch(ratingSummaryProvider(p.workerId)).asData?.value,
      };
      final ordered = orderProposals(proposals, (id) => summaries[id]);
      final recommendedId =
          recommendedProposalId(proposals, (id) => summaries[id]);
      return ClientProposalsViewData(
        headerSubtitle: proposalsHeaderSubtitle(serviceLabel, ordered.length),
        proposals: [
          for (final p in ordered)
            _cardData(
              p,
              summaries[p.workerId],
              p.id == recommendedId,
              includeOptions,
            ),
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
          onOpenProposal: (p) =>
              context.push('/client/job/$jobId/proposals/${p.proposalId}'),
        ),
      ),
    );
  }

  ClientProposalCardViewData _cardData(
    JobProposal p,
    RatingSummary? summary,
    bool recommended,
    List<ProposalIncludeOption> includeOptions,
  ) {
    final name =
        p.workerName?.isNotEmpty == true ? p.workerName! : 'Jardineiro';
    final duration = proposalDurationLabel(p);
    return ClientProposalCardViewData(
      proposalId: p.id,
      workerId: p.workerId,
      workerName: name,
      workerAvatarUrl: p.workerAvatarUrl,
      ratingLabel: proposalRatingLabel(summary),
      priceLabel: proposalValueLabel(p),
      priceKindLabel: proposalPriceKindLabel(p),
      totalLabel: proposalTotalLabel(p),
      totalNoteLabel: proposalTotalNoteLabel(p),
      includesLabel: proposalIncludesSummaryLabel(p, includeOptions)
          ?.toLowerCase(),
      durationLabel: duration.isEmpty ? null : duration,
      scheduleLabel: proposalScheduleLabel(p),
      validUntilLabel: proposalValidUntilLabel(p),
      teamLabel: proposalTeamLabel(p),
      notes: p.notes,
      recommended: recommended,
      expired: p.isExpired,
    );
  }
}
