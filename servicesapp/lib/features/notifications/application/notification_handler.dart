import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/notification_model.dart';
import '../data/notification_types.dart';

class NotificationHandler {
  /// Call this when a notification is tapped.
  /// Navigates to the relevant screen based on notification type.
  static void handle(BuildContext context, AppNotification notification) {
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
      case NotificationType.jobMarkedDone:
      case NotificationType.jobCompleted:
      case NotificationType.jobNoResponse:
      case NotificationType.rescheduleProposed:
      case NotificationType.rescheduleAccepted:
      case NotificationType.rescheduleRejected:
        break;
      default:
        break;
    }
  }
}
