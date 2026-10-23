import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../../help_requests/application/help_request_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../ratings/application/rating_providers.dart';
import '../../worker/application/worker_job_board_providers.dart';
import '../data/notification_model.dart';
import '../data/notification_repository.dart';
import '../data/notification_types.dart';

/// "Os meus trabalhos" (`worker_jobs_screen.dart`) passou a ler
/// `workerJobBoardPageProvider` (migration 0035 — board unificado
/// responsável + ajudante) em vez das 3 tabs separadas + candidaturas.
/// Sempre que um evento já invalidava algum desses providers antigos
/// (mantidos vivos para o dashboard e o detalhe do job — ver
/// `worker_dashboard_screen.dart`/`worker_my_job_detail_screen.dart`),
/// invalida também a página 0 das 3 tabs do board, para o ecrã continuar a
/// refletir mudanças em tempo real sem precisar de pull-to-refresh manual.
void _invalidateWorkerJobBoard(Ref ref) {
  ref.invalidate(workerJobBoardPageProvider(('pending', 0)));
  ref.invalidate(workerJobBoardPageProvider(('scheduled', 0)));
  ref.invalidate(workerJobBoardPageProvider(('completed', 0)));
}

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(supabaseClientProvider)),
);

/// Stream of unread notifications — drives the badge counter and "Novas" section.
final notificationsStreamProvider =
    StreamProvider<List<AppNotification>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.empty();
  return ref.read(notificationRepositoryProvider).streamNotifications(user.id);
});

/// Full history (read + unread) — used by the notifications screen.
final allNotificationsProvider = FutureProvider<List<AppNotification>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref
      .read(notificationRepositoryProvider)
      .fetchAllNotifications(user.id);
});

/// Unread count — derived from the stream, used for the badge.
final unreadCountProvider = Provider<int>((ref) {
  final notifications =
      ref.watch(notificationsStreamProvider).asData?.value ?? [];
  return notifications.where((n) => !n.read).length;
});

/// Side-effect provider: invalidates data providers when new notifications arrive.
/// Keep this provider watched in the app root (App widget).
final notificationSyncProvider = Provider<void>((ref) {
  ref.listen(notificationsStreamProvider, (prev, next) {
    final prevList = prev?.asData?.value ?? [];
    final nextList = next.asData?.value ?? [];

    // Compara ids e não tamanhos: se uma notificação é marcada como lida ao
    // mesmo tempo que chega outra, a lista de não lidas fica com o mesmo
    // tamanho e a nova era ignorada (review 2026-10-16, B3).
    final prevIds = {for (final p in prevList) p.id};
    final newNotifications =
        nextList.where((n) => !prevIds.contains(n.id)).toList();
    if (newNotifications.isEmpty) return;

    for (final notification in newNotifications) {
      switch (notification.type) {
        case NotificationType.newJobInRadius:
        case NotificationType.directJobRequest:
        case NotificationType.jobOpportunityReminder:
          ref.invalidate(jobsInRadiusProvider);
        case NotificationType.proposalReceived:
          ref.invalidate(clientJobsProvider);
          ref.invalidate(pendingProposalsForJobProvider);
          ref.invalidate(pendingWorkerProposalsProvider);
          ref.invalidate(scheduledWorkerProposalsProvider);
          ref.invalidate(completedWorkerProposalsProvider(0));
          _invalidateWorkerJobBoard(ref);
          if (notification.relatedId != null) ref.invalidate(jobByIdProvider(notification.relatedId!));
        case NotificationType.proposalWithdrawn:
          ref.invalidate(clientJobsProvider);
          ref.invalidate(pendingProposalsForJobProvider);
          ref.invalidate(jobsInRadiusProvider);
          ref.invalidate(workerProposalForJobProvider);
          // proposal_count do pedido mudou (detalhe e prazo de expiração).
          if (notification.relatedId != null) ref.invalidate(jobByIdProvider(notification.relatedId!));
        case NotificationType.proposalAccepted:
          ref.invalidate(jobsInRadiusProvider);
          ref.invalidate(pendingWorkerProposalsProvider);
          ref.invalidate(scheduledWorkerProposalsProvider);
          ref.invalidate(completedWorkerProposalsProvider(0));
          _invalidateWorkerJobBoard(ref);
          ref.invalidate(proposalByIdProvider);
          ref.invalidate(workerProposalForJobProvider);
          ref.invalidate(jobByIdProvider);
        case NotificationType.proposalRejected:
          ref.invalidate(jobsInRadiusProvider);
          ref.invalidate(pendingWorkerProposalsProvider);
          ref.invalidate(scheduledWorkerProposalsProvider);
          ref.invalidate(completedWorkerProposalsProvider(0));
          _invalidateWorkerJobBoard(ref);
          ref.invalidate(proposalByIdProvider);
          ref.invalidate(workerProposalForJobProvider);
        case NotificationType.jobCancelled:
        case NotificationType.jobReopened:
          ref.invalidate(clientJobsProvider);
          ref.invalidate(pendingWorkerProposalsProvider);
          ref.invalidate(scheduledWorkerProposalsProvider);
          ref.invalidate(completedWorkerProposalsProvider(0));
          _invalidateWorkerJobBoard(ref);
          ref.invalidate(jobsInRadiusProvider);
          ref.invalidate(jobByIdProvider);
        case NotificationType.rescheduleProposed:
        case NotificationType.rescheduleAccepted:
        case NotificationType.rescheduleRejected:
        case NotificationType.jobReminder:
          ref.invalidate(clientJobsProvider);
          ref.invalidate(pendingWorkerProposalsProvider);
          ref.invalidate(scheduledWorkerProposalsProvider);
          ref.invalidate(completedWorkerProposalsProvider(0));
          _invalidateWorkerJobBoard(ref);
          ref.invalidate(jobByIdProvider);
        case NotificationType.jobStarted:
        case NotificationType.jobMarkedDone:
          ref.invalidate(clientJobsProvider);
          ref.invalidate(jobByIdProvider);
        case NotificationType.jobCompleted:
          ref.invalidate(scheduledWorkerProposalsProvider);
          ref.invalidate(completedWorkerProposalsProvider(0));
          _invalidateWorkerJobBoard(ref);
          ref.invalidate(jobByIdProvider);
          ref.invalidate(clientJobsProvider);
          if (notification.relatedId != null) ref.invalidate(myRatingForJobProvider(notification.relatedId!));
          ref.invalidate(myRatingForJobAndRateeProvider);
        case NotificationType.jobNoResponse:
        case NotificationType.directRequestReleased:
        case NotificationType.jobNoProposalsYet:
          ref.invalidate(clientJobsProvider);
          // O pedido passou a `no_response`: o detalhe aberto tem de mudar.
          if (notification.relatedId != null) ref.invalidate(jobByIdProvider(notification.relatedId!));
        case NotificationType.helpRequestApproved:
          // Principal worker's help_request moved from pending_approval → open.
          ref.invalidate(helpRequestsForJobProvider);
        case NotificationType.helpAccepted:
          ref.invalidate(jobByIdProvider);
          ref.invalidate(myHelpAcceptancesProvider);
          _invalidateWorkerJobBoard(ref);
        case NotificationType.helpRejected:
          ref.invalidate(myHelpAcceptancesProvider);
        case NotificationType.helpJobCancelled:
          // Helper's accepted job was cancelled. Refresh the discovery screen
          // so the cancelled job no longer appears in results.
          ref.invalidate(helpRequestSummariesInRadiusProvider);
          ref.invalidate(helpRequestsInRadiusProvider);
          ref.invalidate(myHelpAcceptancesProvider);
          _invalidateWorkerJobBoard(ref);
        case NotificationType.helpRequestReopened:
        case NotificationType.newHelpRequestInRadius:
          // A slot reopened for a help_request the candidate was rejected from.
          // Refresh the discovery screen so they can see and re-apply to it.
          ref.invalidate(helpRequestSummariesInRadiusProvider);
          ref.invalidate(helpRequestsInRadiusProvider);
        case NotificationType.helpWithdrew:
          // A helper withdrew from the principal's team. Lobby data changes:
          // the help_request may have reverted from 'filled' to 'open'.
          ref.invalidate(helpRequestsForJobProvider);
          ref.invalidate(candidatesForHelpRequestProvider);
        case NotificationType.helpCandidateApplied:
        case NotificationType.helpRequestClosed:
        case NotificationType.helpRequestClosingSoon:
          // 0048: novo candidato na equipa do responsável. 0054: o pedido
          // fechou no dia do trabalho. 0055: fecha esta noite.
          ref.invalidate(helpRequestsForJobProvider);
          ref.invalidate(candidatesForHelpRequestProvider);
        case NotificationType.helpRequestPendingApproval:
        case NotificationType.helpRequestAutoApproved:
          // 0048: só o cliente recebe; o detalhe do pedido mostra o pedido
          // de ajudantes por aprovar.
          ref.invalidate(clientJobsProvider);
          ref.invalidate(helpRequestsForJobProvider);
          if (notification.relatedId != null) ref.invalidate(jobByIdProvider(notification.relatedId!));
        case NotificationType.jobUpdated:
          // 0049: o cliente alterou um pedido a que este jardineiro propôs.
          ref.invalidate(jobsInRadiusProvider);
          ref.invalidate(pendingWorkerProposalsProvider);
          ref.invalidate(workerProposalForJobProvider);
          _invalidateWorkerJobBoard(ref);
          if (notification.relatedId != null) ref.invalidate(jobByIdProvider(notification.relatedId!));
        case NotificationType.helpRemoved:
        case NotificationType.helpJobRescheduled:
        case NotificationType.helpJobDone:
        case NotificationType.helpJobStarted:
          // 0049: avisos ao ajudante sobre o trabalho em que ajuda.
          ref.invalidate(myHelpAcceptancesProvider);
          ref.invalidate(helpRequestSummariesInRadiusProvider);
          _invalidateWorkerJobBoard(ref);
        case NotificationType.helpJobCompleted:
          ref.invalidate(myHelpAcceptancesProvider);
          _invalidateWorkerJobBoard(ref);
          if (notification.relatedId != null) ref.invalidate(myRatingForJobProvider(notification.relatedId!));
      }
    }
    ref.invalidate(allNotificationsProvider);
  });
});
