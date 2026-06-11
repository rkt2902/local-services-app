import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../../jobs/application/job_providers.dart';
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
    final prevList = prev?.asData?.value ?? [];
    final nextList = next.asData?.value ?? [];
    if (nextList.length <= prevList.length) return;

    final newNotifications = nextList
        .where((n) => !prevList.any((p) => p.id == n.id))
        .toList();

    for (final notification in newNotifications) {
      switch (notification.type) {
        case NotificationType.newJobInRadius:
          ref.invalidate(jobsInRadiusProvider);
        case NotificationType.proposalReceived:
          ref.invalidate(clientJobsProvider);
        case NotificationType.proposalAccepted:
        case NotificationType.proposalRejected:
          ref.invalidate(jobsInRadiusProvider);
      }
    }
  });
});
