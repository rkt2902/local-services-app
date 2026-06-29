import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/enums.dart';
import '../../auth/application/session_provider.dart';
import '../../help_requests/application/help_request_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../data/notification_model.dart';
import '../data/notification_types.dart';

class NotificationHandler {
  static Future<void> handle(
      BuildContext context, WidgetRef ref, AppNotification notification) async {
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
        ref.invalidate(clientJobsProvider);
        context.go('/client/jobs');
      case NotificationType.helpRequestApproved:
        // related_id = help_request_id — fetch once to resolve job_id,
        // then navigate directly (screen loads its own data via provider).
        if (notification.relatedId == null) break;
        final helpRequestApproved = await ref
            .read(helpRequestRepositoryProvider)
            .fetchHelpRequestById(notification.relatedId!);
        if (helpRequestApproved == null || !context.mounted) break;
        context.push(
          '/worker/job/${helpRequestApproved.jobId}/help-requests',
        );
      case NotificationType.helpAccepted:
        context.go('/worker/help-requests',
            extra: {'initialTabIndex': 1});
      case NotificationType.helpRejected:
        break; // Informational only; no navigation needed.
      case NotificationType.helpJobCancelled:
        context.go('/worker/help-requests',
            extra: {'initialTabIndex': 1});
      case NotificationType.helpRequestReopened:
        // A slot reopened; take the candidate to the discovery screen to re-apply.
        context.push('/worker/help-requests');
      case NotificationType.helpWithdrew:
        // Principal worker is told a helper withdrew.
        // related_id = help_request_id — fetch once to resolve job_id.
        if (notification.relatedId == null) break;
        final helpRequestWithdrew = await ref
            .read(helpRequestRepositoryProvider)
            .fetchHelpRequestById(notification.relatedId!);
        if (helpRequestWithdrew == null || !context.mounted) break;
        context.push(
          '/worker/job/${helpRequestWithdrew.jobId}/help-requests',
        );
      // unreachable: all NotificationType cases handled above
    }
  }
}
