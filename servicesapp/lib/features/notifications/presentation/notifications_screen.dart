import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/notification_model.dart';
import '../data/notification_types.dart';
import '../application/notification_handler.dart';
import '../application/notification_providers.dart';
import '../../auth/application/auth_providers.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = ref.read(currentUserProvider);
      if (user != null) {
        ref.read(notificationRepositoryProvider).markAllAsRead(user.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationsStreamProvider);
    final unreadCount = ref.watch(unreadCountProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: user == null
                  ? null
                  : () => ref
                      .read(notificationRepositoryProvider)
                      .markAllAsRead(user.id),
              child: const Text('Marcar todas como lidas'),
            ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('Sem notificações.'),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: notifications.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) =>
                _NotificationTile(notification: notifications[index]),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (icon, color) = _iconForType(notification.type);

    return Material(
      color: notification.read
          ? null
          : theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(
          notification.title,
          style: notification.read
              ? null
              : const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.body),
            const SizedBox(height: 2),
            Text(
              _relativeTime(notification.createdAt),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        isThreeLine: true,
        onTap: () {
          NotificationHandler.handle(context, ref, notification);
          ref
              .read(notificationRepositoryProvider)
              .markAsRead(notification.id);
        },
      ),
    );
  }
}

(IconData, Color) _iconForType(String type) => switch (type) {
      NotificationType.newJobInRadius => (Icons.yard, Colors.green.shade600),
      NotificationType.proposalReceived =>
        (Icons.description, Colors.orange.shade700),
      NotificationType.proposalAccepted =>
        (Icons.check_circle, Colors.green.shade600),
      NotificationType.proposalRejected =>
        (Icons.cancel, Colors.red.shade600),
      _ => (Icons.notifications, Colors.grey.shade500),
    };

String _relativeTime(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours}h';
  return 'há ${diff.inDays} dia${diff.inDays > 1 ? 's' : ''}';
}
