import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ratings/application/rating_providers.dart';
import '../../../ratings/presentation/submit_rating_sheet.dart';
import '../../data/help_request_model.dart';
import '../../../../core/widgets/app_confirm_dialog.dart';

/// Diálogo de confirmação partilhado por "Retirar candidatura" (pendente) e
/// "Desistir" (aceite), usado na tab "As minhas candidaturas" e no ecrã do
/// ajudante.
Future<bool> confirmHelperWithdraw(
  BuildContext context, {
  required bool isPending,
}) async {
  final confirmed = await AppConfirmDialog.show(
    context,
    icon: isPending ? Icons.undo_rounded : Icons.person_remove_outlined,
    title: isPending ? 'Retirar candidatura?' : 'Desistir desta ajuda?',
    message: isPending
        ? 'A tua candidatura deixa de aparecer ao jardineiro responsável.'
        : 'O jardineiro responsável vai ser avisado.',
    confirmLabel: isPending ? 'Retirar' : 'Desistir',
    destructive: true,
  );
  return confirmed == true;
}

/// Sheet "Avaliar o jardineiro responsável" (`submit_helper_rating`).
/// Devolve `true` quando a avaliação foi enviada; invalida as avaliações
/// do próprio pedido e a lista de avaliações dadas.
Future<bool> showRatePrincipalSheet(
  BuildContext context,
  WidgetRef ref,
  HelpAcceptanceSummary acceptance,
) async {
  final jobId = acceptance.jobId;
  // Lido antes de abrir a folha (o `ref` pode deixar de servir se o ecrã
  // por trás recarregar enquanto a folha está aberta).
  final repo = ref.read(ratingRepositoryProvider);
  final submitted = await showSubmitRatingSheet(
    context: context,
    title: 'Avaliar o jardineiro responsável',
    subtitle: acceptance.principalName,
    successMessage: 'Avaliação enviada!',
    onSubmit: (stars, comment) async {
      await repo.submitHelperRating(
            jobId: jobId,
            stars: stars,
            comment: comment,
          );
    },
  );
  if (submitted != true || !context.mounted) return false;
  ref.invalidate(myRatingForJobProvider(jobId));
  ref.invalidate(myRatingsGivenProvider);
  return true;
}
