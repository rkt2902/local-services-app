import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../help_requests/application/help_request_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../proposals/application/proposal_providers.dart';
import 'worker_job_board_providers.dart';

/// Invalida todas as listas do lado do worker que uma ação dele pode mudar:
/// o board "Os meus trabalhos" (todas as tabs e páginas), as listas antigas
/// de propostas (dashboard e contagens), as candidaturas de ajudante, as
/// oportunidades no raio e a proposta do worker para cada pedido.
///
/// Regra T4: chamar sempre DEPOIS de navegar e de mostrar o SnackBar.
/// Passa [jobId] para invalidar também o detalhe desse pedido.
void invalidateWorkerLists(WidgetRef ref, {String? jobId}) {
  ref.invalidate(workerJobBoardPageProvider);
  ref.invalidate(pendingWorkerProposalsProvider);
  ref.invalidate(scheduledWorkerProposalsProvider);
  ref.invalidate(completedWorkerProposalsProvider);
  ref.invalidate(workerProposalForJobProvider);
  ref.invalidate(myHelpAcceptancesProvider);
  ref.invalidate(helpRequestSummariesInRadiusProvider);
  ref.invalidate(helpRequestsInRadiusProvider);
  ref.invalidate(jobsInRadiusProvider);
  if (jobId != null && jobId.isNotEmpty) {
    ref.invalidate(jobByIdProvider(jobId));
    ref.invalidate(jobWorkDaysProvider(jobId));
  }
}
