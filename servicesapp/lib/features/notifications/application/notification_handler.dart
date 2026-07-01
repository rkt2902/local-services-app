import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/enums.dart';
import '../../auth/application/session_provider.dart';
import '../../help_requests/application/help_request_providers.dart';
import '../../proposals/application/proposal_providers.dart';
import '../data/notification_model.dart';
import '../data/notification_types.dart';

class NotificationHandler {
  static Future<void> handle(
      BuildContext context, WidgetRef ref, AppNotification notification) async {
    switch (notification.type) {
      // ── Job discovery ─────────────────────────────────────────────────────
      case NotificationType.newJobInRadius:
        // relatedId = job_id — push so the worker can navigate back.
        if (notification.relatedId == null) break;
        context.push('/worker/job/${notification.relatedId}');

      // ── Proposal lifecycle (client-facing) ────────────────────────────────
      case NotificationType.proposalReceived:
      case NotificationType.proposalWithdrawn:
        // relatedId = job_id. Use go (not push) so that if the client is
        // already on this job's screen, we replace rather than stack — this
        // prevents the RT1 keyReservation assertion crash on duplicate push.
        if (notification.relatedId == null) break;
        context.go('/client/job/${notification.relatedId}');

      // ── Proposal lifecycle (worker-facing) ────────────────────────────────
      case NotificationType.proposalAccepted:
        // relatedId = job_id. Resolve proposalId via async fetch, then go
        // to the worker's confirmed job detail.
        // RT4: two-level fallback replaces the previous silent null break.
        if (notification.relatedId == null) break;
        final acceptedProposal = await ref
            .read(proposalRepositoryProvider)
            .fetchAcceptedProposalForJob(notification.relatedId!);
        if (!context.mounted) break;
        if (acceptedProposal != null) {
          context.go(
            '/worker/my-job/${acceptedProposal.id}?jobId=${notification.relatedId}',
          );
        } else {
          context.go('/worker/home');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Não foi possível abrir o job. Verifica a lista de jobs.'),
            ),
          );
        }

      case NotificationType.proposalRejected:
        // relatedId = job_id — push so the worker can navigate back.
        if (notification.relatedId == null) break;
        context.push('/worker/job/${notification.relatedId}');

      // ── Job lifecycle ─────────────────────────────────────────────────────
      case NotificationType.jobCancelled:
        // Sent to the party that did NOT cancel. relatedId = job_id.
        // Client: go directly. Worker: resolve proposalId first (proposal may
        // retain status='accepted' on a cancelled job_request).
        if (notification.relatedId == null) break;
        final sessionCancelled = ref.read(sessionStatusProvider).asData?.value;
        if (sessionCancelled?.role == UserRole.client) {
          context.go('/client/job/${notification.relatedId}');
        } else {
          final proposal = await ref
              .read(proposalRepositoryProvider)
              .fetchAcceptedProposalForJob(notification.relatedId!);
          if (!context.mounted) break;
          if (proposal != null) {
            context.go(
                '/worker/my-job/${proposal.id}?jobId=${notification.relatedId}');
          } else {
            context.go('/worker/home');
          }
        }

      case NotificationType.jobReopened:
        // Sent to workers whose proposals were on the original cancelled job.
        // relatedId = job_id — push to the discovery view (can navigate back).
        if (notification.relatedId == null) break;
        context.push('/worker/job/${notification.relatedId}');

      case NotificationType.rescheduleProposed:
      case NotificationType.rescheduleAccepted:
      case NotificationType.rescheduleRejected:
        // Sent to the OTHER party (the one who did not initiate the reschedule).
        // relatedId = job_id. Client: go directly. Worker: resolve proposalId first.
        if (notification.relatedId == null) break;
        final sessionReschedule =
            ref.read(sessionStatusProvider).asData?.value;
        if (sessionReschedule?.role == UserRole.client) {
          context.go('/client/job/${notification.relatedId}');
        } else {
          final proposal = await ref
              .read(proposalRepositoryProvider)
              .fetchAcceptedProposalForJob(notification.relatedId!);
          if (!context.mounted) break;
          if (proposal != null) {
            context.go(
                '/worker/my-job/${proposal.id}?jobId=${notification.relatedId}');
          } else {
            context.go('/worker/home');
          }
        }

      case NotificationType.jobMarkedDone:
        // Sent to client only — worker marked the job done, awaiting confirmation.
        // relatedId = job_id — client goes directly to confirm or report a problem.
        if (notification.relatedId == null) break;
        context.go('/client/job/${notification.relatedId}');

      case NotificationType.jobCompleted:
        // Sent to both sides when the job is fully confirmed. relatedId = job_id.
        // Client: go directly. Worker: resolve proposalId first.
        if (notification.relatedId == null) break;
        final sessionCompleted = ref.read(sessionStatusProvider).asData?.value;
        if (sessionCompleted?.role == UserRole.client) {
          context.go('/client/job/${notification.relatedId}');
        } else {
          final proposal = await ref
              .read(proposalRepositoryProvider)
              .fetchAcceptedProposalForJob(notification.relatedId!);
          if (!context.mounted) break;
          if (proposal != null) {
            context.go(
                '/worker/my-job/${proposal.id}?jobId=${notification.relatedId}');
          } else {
            context.go('/worker/home');
          }
        }

      case NotificationType.jobNoResponse:
        // Sent to client only — job expired without proposals. relatedId = job_id.
        if (notification.relatedId == null) break;
        context.go('/client/job/${notification.relatedId}');

      // ── Help-request lifecycle ────────────────────────────────────────────
      case NotificationType.helpRequestApproved:
        // relatedId = help_request_id. Resolve job_id via fetch, then push
        // principal to the lobby (can navigate back). Fallback to home if null.
        if (notification.relatedId == null) break;
        final helpRequestApproved = await ref
            .read(helpRequestRepositoryProvider)
            .fetchHelpRequestById(notification.relatedId!);
        if (!context.mounted) break;
        if (helpRequestApproved != null) {
          context.push(
              '/worker/job/${helpRequestApproved.jobId}/help-requests');
        } else {
          context.go('/worker/home');
        }

      case NotificationType.helpAccepted:
        // relatedId = help_request_id. Helper sees their candidatures.
        context.go('/worker/help-requests', extra: {'initialTabIndex': 1});

      case NotificationType.helpRejected:
        // Helper was rejected — navigate to candidatures tab to see the update.
        context.go('/worker/help-requests', extra: {'initialTabIndex': 1});

      case NotificationType.helpJobCancelled:
        // Helper's accepted job was cancelled — navigate to candidatures.
        context.go('/worker/help-requests', extra: {'initialTabIndex': 1});

      case NotificationType.helpRequestReopened:
        // A slot reopened — push to discovery so the candidate can re-apply.
        context.push('/worker/help-requests');

      case NotificationType.helpWithdrew:
        // Principal is told a helper withdrew. relatedId = help_request_id.
        // Resolve job_id via fetch, then push to the lobby. Fallback to home.
        if (notification.relatedId == null) break;
        final helpRequestWithdrew = await ref
            .read(helpRequestRepositoryProvider)
            .fetchHelpRequestById(notification.relatedId!);
        if (!context.mounted) break;
        if (helpRequestWithdrew != null) {
          context.push(
              '/worker/job/${helpRequestWithdrew.jobId}/help-requests');
        } else {
          context.go('/worker/home');
        }
    }
  }
}
