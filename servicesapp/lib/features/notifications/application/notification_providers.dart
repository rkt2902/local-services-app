import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../proposals/application/proposal_providers.dart';
import '../data/notification_model.dart';
import '../data/notification_repository.dart';
import '../data/notification_types.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(supabaseClientProvider)),
);

/// Stream of all notifications for the current user.
/// Used by both the notification screen and the badge counter.
final notificationsStreamProvider =
    StreamProvider<List<AppNotification>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.empty();
  return ref.read(notificationRepositoryProvider).streamNotifications(user.id);
});

/// Unread count — derived from the stream, used for the badge.
final unreadCountProvider = Provider<int>((ref) {
  final notifications =
      ref.watch(notificationsStreamProvider).asData?.value ?? [];
  return notifications.where((n) => !n.read).length;
});

/// Side-effect provider: invalidates data providers when notifications arrive.
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
          ref.invalidate(workerProposalsProvider);
        case NotificationType.proposalWithdrawn:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          ref.invalidate(clientJobsProvider);
          ref.invalidate(pendingProposalsForJobProvider);
          ref.invalidate(jobsInRadiusProvider);
          ref.invalidate(workerProposalForJobProvider);
        // DB trigger on_proposal_updated was removed — it was duplicating
        // proposalAccepted/proposalRejected notifications already inserted by
        // the accept_proposal and reject_proposal RPCs.
        // These notification types now come exclusively from those RPCs.
        case NotificationType.proposalAccepted:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          ref.invalidate(jobsInRadiusProvider);
          ref.invalidate(workerProposalsProvider);
          ref.invalidate(proposalByIdProvider);
          ref.invalidate(workerProposalForJobProvider);
        case NotificationType.proposalRejected:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          ref.invalidate(jobsInRadiusProvider);
          ref.invalidate(workerProposalsProvider);
          ref.invalidate(proposalByIdProvider);
        case NotificationType.jobCancelled:
        case NotificationType.jobReopened:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          ref.invalidate(clientJobsProvider);
          ref.invalidate(workerProposalsProvider);
          ref.invalidate(jobsInRadiusProvider);
        case NotificationType.rescheduleProposed:
        case NotificationType.rescheduleAccepted:
        case NotificationType.rescheduleRejected:
          debugPrint('notificationSync: invalidating for type=${notification.type}');
          ref.invalidate(clientJobsProvider);
          ref.invalidate(workerProposalsProvider);
        case NotificationType.jobMarkedDone:
        case NotificationType.jobCompleted:
        case NotificationType.jobNoResponse:
          break;
      }
    }
  });
});
