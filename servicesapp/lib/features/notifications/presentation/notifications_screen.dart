import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/notification_model.dart';
import '../data/notification_types.dart';
import '../application/notification_handler.dart';
import '../application/notification_providers.dart';
import '../../auth/application/auth_providers.dart';
import '../../../core/utils/error_utils.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _optimisticClear = false;

  Future<void> _clearAll() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final repo = ref.read(notificationRepositoryProvider);
    final scaffold = ScaffoldMessenger.of(context);
    setState(() => _optimisticClear = true);
    try {
      await repo.markAllAsRead(user.id);
      ref.invalidate(allNotificationsProvider);
    } catch (e) {
      if (mounted) {
        setState(() => _optimisticClear = false);
        scaffold.showSnackBar(
            SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _optimisticClear = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadAsync = ref.watch(notificationsStreamProvider);
    final allAsync = ref.watch(allNotificationsProvider);

    if (unreadAsync.isLoading || allAsync.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (unreadAsync.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notificações')),
        body: Center(child: Text(friendlyError(unreadAsync.error!))),
      );
    }

    final unread = _optimisticClear
        ? <AppNotification>[]
        : (unreadAsync.asData?.value ?? <AppNotification>[]);
    final all = allAsync.asData?.value ?? <AppNotification>[];
    final unreadIds = unread.map((n) => n.id).toSet();
    final read =
        all.where((n) => !unreadIds.contains(n.id) && n.read).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        actions: [
          if (unread.isNotEmpty)
            TextButton(
              onPressed: _clearAll,
              child: const Text('Limpar'),
            ),
        ],
      ),
      body: (unread.isEmpty && read.isEmpty)
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('Sem notificações.'),
                ],
              ),
            )
          : ListView(
              children: [
                if (unread.isNotEmpty) ...[
                  const _SectionHeader('Novas'),
                  ...unread.map((n) => _NotificationTile(notification: n)),
                  const Divider(height: 1),
                ],
                if (read.isNotEmpty) ...[
                  const _SectionHeader('Anteriores'),
                  ...read.map((n) => _NotificationTile(notification: n)),
                ],
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
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
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            isThreeLine: true,
            onTap: () {
              NotificationHandler.handle(context, ref, notification);
              ref
                  .read(notificationRepositoryProvider)
                  .markAsRead(notification.id);
              ref.invalidate(allNotificationsProvider);
            },
          ),
        ),
        const Divider(height: 1),
      ],
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
