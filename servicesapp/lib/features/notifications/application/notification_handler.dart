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
      // ── Job discovery ─────────────────────────────────────────────────────
      case NotificationType.newJobInRadius:
        // relatedId = job_id — take worker directly to the specific job.
        if (notification.relatedId != null) {
          context.push('/worker/job/${notification.relatedId}');
        }

      // ── Proposal lifecycle (client-facing) ────────────────────────────────
      case NotificationType.proposalReceived:
      case NotificationType.proposalWithdrawn:
        // relatedId = job_id — take client directly to the job detail.
        if (notification.relatedId != null) {
          context.push('/client/job/${notification.relatedId}');
        }

      // ── Proposal lifecycle (worker-facing) ────────────────────────────────
      case NotificationType.proposalAccepted:
        // relatedId = job_id. Worker's proposal was accepted → navigate to
        // the confirmed job detail screen, which needs the proposal ID.
        // Fetch the accepted proposal for this job, then deep-link.
        if (notification.relatedId == null) break;
        final acceptedProposal = await ref
            .read(proposalRepositoryProvider)
            .fetchAcceptedProposalForJob(notification.relatedId!);
        if (acceptedProposal == null || !context.mounted) break;
        context.push(
          '/worker/my-job/${acceptedProposal.id}?jobId=${notification.relatedId}',
        );

      case NotificationType.proposalRejected:
        // relatedId = job_id. Worker's proposal was rejected — navigate to
        // the job view so they can see the rejection context.
        if (notification.relatedId != null) {
          context.push('/worker/job/${notification.relatedId}');
        }

      // ── Job lifecycle ─────────────────────────────────────────────────────
      // TODO T6: deep-link using relatedId (= job_id) for each type.
      // Requires worker-facing types to also resolve proposalId via
      // fetchAcceptedProposalForJob before pushing /worker/my-job.
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

      // ── Help-request lifecycle ────────────────────────────────────────────
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
        // relatedId = help_request_id. Passing a primitive tab index via
        // extra is safe here (no stale domain-object reference, no redirect
        // risk on a list screen). No change from original behavior.
        context.go('/worker/help-requests',
            extra: {'initialTabIndex': 1});

      case NotificationType.helpRejected:
        break; // Informational only; no navigation needed.

      case NotificationType.helpJobCancelled:
        // Same safe-extra judgment as helpAccepted above.
        context.go('/worker/help-requests',
            extra: {'initialTabIndex': 1});

      case NotificationType.helpRequestReopened:
        // A slot reopened; take candidate to discovery to re-apply.
        // Navigation to the specific help_request inside the discovery
        // list is not yet supported — the list is the correct target.
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
