import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/enums.dart';
import '../../auth/application/session_provider.dart';
import '../data/notification_model.dart';
import '../data/notification_types.dart';

class NotificationHandler {
  static void handle(
      BuildContext context, WidgetRef ref, AppNotification notification) {
    switch (notification.type) {
      case NotificationType.newJobInRadius:
        if (notification.relatedId != null) {
          context.go('/worker/home');
        }
      case NotificationType.proposalReceived:
      case NotificationType.proposalWithdrawn:
        if (notification.relatedId != null) {
          context.go('/client/jobs');
        }
      case NotificationType.proposalAccepted:
      case NotificationType.proposalRejected:
        context.go('/worker/home');
      case NotificationType.jobCancelled:
      case NotificationType.jobReopened:
      case NotificationType.rescheduleProposed:
      case NotificationType.rescheduleAccepted:
      case NotificationType.rescheduleRejected:
        final session = ref.read(sessionStatusProvider).asData?.value;
        if (session?.role == UserRole.client) {
          context.go('/client/jobs');
        } else {
          context.go('/worker/home');
        }
      case NotificationType.jobMarkedDone:
      case NotificationType.jobCompleted:
        final session = ref.read(sessionStatusProvider).asData?.value;
        if (session?.role == UserRole.client) {
          context.go('/client/jobs');
        } else {
          context.go('/worker/home');
        }
      case NotificationType.jobNoResponse:
        break;
      // unreachable: all NotificationType cases handled above
    }
  }
}
