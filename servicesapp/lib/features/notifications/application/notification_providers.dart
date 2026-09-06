import 'package:flutter/foundation.dart';
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
    debugPrint('notificationSync fired: prev=${prev?.asData?.value.length} next=${next.asData?.value.length}');
    final prevList = prev?.asData?.value ?? [];
    final nextList = next.asData?.value ?? [];
    if (nextList.length <= prevList.length) return;

    final newNotifications = nextList
        .where((n) => !prevList.any((p) => p.id == n.id))
        .toList();

    for (final notification in newNotifications) {
      switch (notification.type) {
        case NotificationType.newJobInRadius:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          ref.invalidate(jobsInRadiusProvider);
        case NotificationType.proposalReceived:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          ref.invalidate(clientJobsProvider);
          ref.invalidate(pendingProposalsForJobProvider);
          ref.invalidate(pendingWorkerProposalsProvider);
          ref.invalidate(scheduledWorkerProposalsProvider);
          ref.invalidate(completedWorkerProposalsProvider(0));
          _invalidateWorkerJobBoard(ref);
          if (notification.relatedId != null) ref.invalidate(jobByIdProvider(notification.relatedId!));
        case NotificationType.proposalWithdrawn:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          ref.invalidate(clientJobsProvider);
          ref.invalidate(pendingProposalsForJobProvider);
          ref.invalidate(jobsInRadiusProvider);
          ref.invalidate(workerProposalForJobProvider);
        case NotificationType.proposalAccepted:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          ref.invalidate(jobsInRadiusProvider);
          ref.invalidate(pendingWorkerProposalsProvider);
          ref.invalidate(scheduledWorkerProposalsProvider);
          ref.invalidate(completedWorkerProposalsProvider(0));
          _invalidateWorkerJobBoard(ref);
          ref.invalidate(proposalByIdProvider);
          ref.invalidate(workerProposalForJobProvider);
          ref.invalidate(jobByIdProvider);
        case NotificationType.proposalRejected:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          ref.invalidate(jobsInRadiusProvider);
          ref.invalidate(pendingWorkerProposalsProvider);
          ref.invalidate(scheduledWorkerProposalsProvider);
          ref.invalidate(completedWorkerProposalsProvider(0));
          _invalidateWorkerJobBoard(ref);
          ref.invalidate(proposalByIdProvider);
          ref.invalidate(workerProposalForJobProvider);
        case NotificationType.jobCancelled:
        case NotificationType.jobReopened:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
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
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          ref.invalidate(clientJobsProvider);
          ref.invalidate(pendingWorkerProposalsProvider);
          ref.invalidate(scheduledWorkerProposalsProvider);
          ref.invalidate(completedWorkerProposalsProvider(0));
          _invalidateWorkerJobBoard(ref);
          ref.invalidate(jobByIdProvider);
        case NotificationType.jobMarkedDone:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          ref.invalidate(clientJobsProvider);
          ref.invalidate(jobByIdProvider);
        case NotificationType.jobCompleted:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          ref.invalidate(scheduledWorkerProposalsProvider);
          ref.invalidate(completedWorkerProposalsProvider(0));
          _invalidateWorkerJobBoard(ref);
          ref.invalidate(jobByIdProvider);
          ref.invalidate(clientJobsProvider);
          if (notification.relatedId != null) ref.invalidate(myRatingForJobProvider(notification.relatedId!));
          ref.invalidate(myRatingForJobAndRateeProvider);
        case NotificationType.jobNoResponse:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          ref.invalidate(clientJobsProvider);
        case NotificationType.helpRequestApproved:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          // Principal worker's help_request moved from pending_approval → open.
          ref.invalidate(helpRequestsForJobProvider);
        case NotificationType.helpAccepted:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          ref.invalidate(jobByIdProvider);
          ref.invalidate(myHelpAcceptancesProvider);
          _invalidateWorkerJobBoard(ref);
        case NotificationType.helpRejected:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          ref.invalidate(myHelpAcceptancesProvider);
        case NotificationType.helpJobCancelled:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          // Helper's accepted job was cancelled. Refresh the discovery screen
          // so the cancelled job no longer appears in results.
          ref.invalidate(helpRequestSummariesInRadiusProvider);
          ref.invalidate(helpRequestsInRadiusProvider);
          ref.invalidate(myHelpAcceptancesProvider);
          _invalidateWorkerJobBoard(ref);
        case NotificationType.helpRequestReopened:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          // A slot reopened for a help_request the candidate was rejected from.
          // Refresh the discovery screen so they can see and re-apply to it.
          ref.invalidate(helpRequestSummariesInRadiusProvider);
          ref.invalidate(helpRequestsInRadiusProvider);
        case NotificationType.helpWithdrew:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          // A helper withdrew from the principal's team. Lobby data changes:
          // the help_request may have reverted from 'filled' to 'open'.
          ref.invalidate(helpRequestsForJobProvider);
      }
    }
    ref.invalidate(allNotificationsProvider);
  });
});
