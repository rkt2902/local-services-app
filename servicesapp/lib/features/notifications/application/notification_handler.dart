import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/enums.dart';
import '../../auth/application/session_provider.dart';
import '../../help_requests/application/help_request_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../proposals/application/proposal_providers.dart';
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
        break;
      case NotificationType.helpRequestApproved:
        // related_id = help_request_id (set by approve_help_request RPC).
        // The lobby route needs job + proposal objects, so we fetch the
        // help_request first to get job_id and proposal_id, then resolve both.
        if (notification.relatedId == null) break;
        final helpRequest = await ref
            .read(helpRequestRepositoryProvider)
            .fetchHelpRequestById(notification.relatedId!);
        if (helpRequest == null || !context.mounted) break;
        final job =
            await ref.read(jobByIdProvider(helpRequest.jobId).future);
        final proposal = await ref
            .read(proposalByIdProvider(helpRequest.proposalId).future);
        if (job == null || proposal == null || !context.mounted) break;
        context.push(
          '/worker/job/${helpRequest.jobId}/help-requests',
          extra: {'job': job, 'proposal': proposal},
        );
      case NotificationType.helpAccepted:
        // TODO: navigate to dedicated helper job detail screen once built.
        context.go('/worker/jobs');
      case NotificationType.helpRejected:
        break; // Informational only; no navigation needed.
      case NotificationType.helpJobCancelled:
        // Helper is told the job they were accepted onto was cancelled.
        // TODO: navigate to dedicated helper job screen once built.
        context.go('/worker/jobs');
      case NotificationType.helpRequestReopened:
        // A slot reopened; take the candidate to the discovery screen to re-apply.
        context.push('/worker/help-requests');
      case NotificationType.helpWithdrew:
        // Principal worker is told a helper withdrew.
        // related_id = help_request_id — navigate to the lobby.
        if (notification.relatedId == null) break;
        final helpRequest = await ref
            .read(helpRequestRepositoryProvider)
            .fetchHelpRequestById(notification.relatedId!);
        if (helpRequest == null || !context.mounted) break;
        final job =
            await ref.read(jobByIdProvider(helpRequest.jobId).future);
        final proposal = await ref
            .read(proposalByIdProvider(helpRequest.proposalId).future);
        if (job == null || proposal == null || !context.mounted) break;
        context.push(
          '/worker/job/${helpRequest.jobId}/help-requests',
          extra: {'job': job, 'proposal': proposal},
        );
      // unreachable: all NotificationType cases handled above
    }
  }
}
