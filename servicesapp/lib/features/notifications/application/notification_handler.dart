import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/enums.dart';
import '../../auth/application/session_provider.dart';
import '../../help_requests/application/help_request_providers.dart';
import '../../help_requests/application/helper_job_state.dart';
import '../../help_requests/data/help_request_model.dart';
import '../../proposals/application/proposal_providers.dart';
import '../data/notification_model.dart';
import '../data/notification_types.dart';
import '../../../core/widgets/app_toast.dart';

class NotificationHandler {
  static Future<void> _openHelperJob(
    BuildContext context,
    WidgetRef ref,
    String? relatedId,
  ) async {
    HelpAcceptanceSummary? acceptance;
    if (relatedId != null) {
      try {
        // A notificação nova já invalidou a lista (notificationSyncProvider).
        final acceptances = await ref.read(myHelpAcceptancesProvider.future);
        acceptance = findHelperAcceptanceFor(acceptances, relatedId);
      } catch (_) {
        acceptance = null;
      }
    }
    if (!context.mounted) return;
    if (acceptance != null) {
      context.go(
        '/worker/help/${acceptance.id}',
        extra: {'entryTransition': 'sharedAxis'},
      );
      return;
    }
    context.go(
      '/worker/help-requests',
      extra: {'initialTabIndex': 1, 'entryTransition': 'sharedAxis'},
    );
  }

  static Future<void> handle(
    BuildContext context,
    WidgetRef ref,
    AppNotification notification,
  ) async {
    switch (notification.type) {
      // ── Job discovery ─────────────────────────────────────────────────────
      case NotificationType.newJobInRadius:
        // relatedId = job_id — go (not push) to avoid keyReservation crash on
        // duplicate push when the worker is already viewing this job.
        if (notification.relatedId == null) break;
        context.go(
          '/worker/job/${notification.relatedId}',
          extra: {'entryTransition': 'sharedAxis'},
        );

      // ── Proposal lifecycle (client-facing) ────────────────────────────────
      case NotificationType.proposalReceived:
      case NotificationType.proposalWithdrawn:
        // relatedId = job_id. Use go (not push) so that if the client is
        // already on this job's screen, we replace rather than stack — this
        // prevents the RT1 keyReservation assertion crash on duplicate push.
        if (notification.relatedId == null) break;
        context.go(
          '/client/job/${notification.relatedId}',
          extra: {'entryTransition': 'sharedAxis'},
        );

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
            extra: {'entryTransition': 'sharedAxis'},
          );
        } else {
          context.go('/worker/home');
          AppToast.of(context).error('Não foi possível abrir o job. Verifica a lista de jobs.');
        }

      case NotificationType.proposalRejected:
        // relatedId = job_id — go (not push) to avoid keyReservation crash.
        if (notification.relatedId == null) break;
        context.go(
          '/worker/job/${notification.relatedId}',
          extra: {'entryTransition': 'sharedAxis'},
        );

      // ── Job lifecycle ─────────────────────────────────────────────────────
      case NotificationType.jobCancelled:
        // Sent to the party that did NOT cancel. relatedId = job_id.
        // Client: go directly. Worker: resolve proposalId first (proposal may
        // retain status='accepted' on a cancelled job_request).
        if (notification.relatedId == null) break;
        final sessionCancelled = ref.read(sessionStatusProvider).asData?.value;
        if (sessionCancelled?.role == UserRole.client) {
          context.go(
            '/client/job/${notification.relatedId}',
            extra: {'entryTransition': 'sharedAxis'},
          );
        } else {
          final proposal = await ref
              .read(proposalRepositoryProvider)
              .fetchAcceptedProposalForJob(notification.relatedId!);
          if (!context.mounted) break;
          if (proposal != null) {
            context.go(
              '/worker/my-job/${proposal.id}?jobId=${notification.relatedId}',
              extra: {'entryTransition': 'sharedAxis'},
            );
          } else {
            context.go('/worker/home');
          }
        }

      case NotificationType.jobReopened:
        // cancel_job (0043) só envia isto ao CLIENTE, quando o jardineiro
        // cancela e o pedido é reaberto. relatedId = id do pedido NOVO.
        // Encaminha pelo papel atual, para nunca mandar um cliente para uma
        // rota /worker/ (o guard cross-role atirava-o para a home).
        if (notification.relatedId == null) break;
        final sessionReopened = ref.read(sessionStatusProvider).asData?.value;
        context.go(
          sessionReopened?.role == UserRole.worker
              ? '/worker/job/${notification.relatedId}'
              : '/client/job/${notification.relatedId}',
          extra: {'entryTransition': 'sharedAxis'},
        );

      case NotificationType.rescheduleProposed:
      case NotificationType.rescheduleAccepted:
      case NotificationType.rescheduleRejected:
        // Sent to the OTHER party (the one who did not initiate the reschedule).
        // relatedId = job_id. Client: go directly. Worker: resolve proposalId first.
        if (notification.relatedId == null) break;
        final sessionReschedule = ref.read(sessionStatusProvider).asData?.value;
        if (sessionReschedule?.role == UserRole.client) {
          context.go(
            '/client/job/${notification.relatedId}',
            extra: {'entryTransition': 'sharedAxis'},
          );
        } else {
          final proposal = await ref
              .read(proposalRepositoryProvider)
              .fetchAcceptedProposalForJob(notification.relatedId!);
          if (!context.mounted) break;
          if (proposal != null) {
            context.go(
              '/worker/my-job/${proposal.id}?jobId=${notification.relatedId}',
              extra: {'entryTransition': 'sharedAxis'},
            );
          } else {
            context.go('/worker/home');
          }
        }

      case NotificationType.jobStarted:
      case NotificationType.jobMarkedDone:
        // jobStarted (0052): o jardineiro começou o trabalho.
        // Sent to client only — worker marked the job done, awaiting confirmation.
        // relatedId = job_id — client goes directly to confirm or report a problem.
        if (notification.relatedId == null) break;
        context.go(
          '/client/job/${notification.relatedId}',
          extra: {'entryTransition': 'sharedAxis'},
        );

      case NotificationType.jobCompleted:
      case NotificationType.jobReminder:
        // jobCompleted: sent to both sides when the job is fully confirmed.
        // jobReminder (0046): morning of the job day, date passed without
        // completion, or completion awaiting the client. relatedId = job_id.
        // Client: go directly. Worker: resolve proposalId first.
        if (notification.relatedId == null) break;
        final sessionCompleted = ref.read(sessionStatusProvider).asData?.value;
        if (sessionCompleted?.role == UserRole.client) {
          context.go(
            '/client/job/${notification.relatedId}',
            extra: {'entryTransition': 'sharedAxis'},
          );
        } else {
          final proposal = await ref
              .read(proposalRepositoryProvider)
              .fetchAcceptedProposalForJob(notification.relatedId!);
          if (!context.mounted) break;
          if (proposal != null) {
            context.go(
              '/worker/my-job/${proposal.id}?jobId=${notification.relatedId}',
              extra: {'entryTransition': 'sharedAxis'},
            );
          } else {
            context.go('/worker/home');
          }
        }

      case NotificationType.jobNoResponse:
        // Sent to client only — job expired without proposals. relatedId = job_id.
        if (notification.relatedId == null) break;
        context.go(
          '/client/job/${notification.relatedId}',
          extra: {'entryTransition': 'sharedAxis'},
        );

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
            '/worker/job/${helpRequestApproved.jobId}/help-requests',
          );
        } else {
          context.go('/worker/home');
        }

      case NotificationType.helpAccepted:
      case NotificationType.helpRejected:
      case NotificationType.helpJobCancelled:
      case NotificationType.helpRemoved:
      case NotificationType.helpJobRescheduled:
      case NotificationType.helpJobDone:
      case NotificationType.helpJobCompleted:
        // Para o ajudante. relatedId = id do pedido (0049) ou do pedido de
        // ajuda (tipos antigos): abre o ecrã da candidatura quando a
        // encontra, senão a tab "As minhas candidaturas".
        await _openHelperJob(context, ref, notification.relatedId);

      case NotificationType.jobUpdated:
        // O cliente alterou um pedido a que o jardineiro propôs (0049).
        // relatedId = job_id. `/worker/job/:id` já trata a proposta dele.
        if (notification.relatedId == null) break;
        context.go(
          '/worker/job/${notification.relatedId}',
          extra: {'entryTransition': 'sharedAxis'},
        );

      case NotificationType.helpRequestReopened:
        // A slot reopened — push to discovery so the candidate can re-apply.
        context.push(
          '/worker/help-requests',
          extra: {'entryTransition': 'sharedAxis'},
        );

      case NotificationType.helpRequestPendingApproval:
        // Só o cliente recebe (0048). relatedId = job_id.
        if (notification.relatedId == null) break;
        context.go('/client/job/${notification.relatedId}');

      case NotificationType.helpCandidateApplied:
      case NotificationType.helpWithdrew:
        // Principal is told a helper applied (0048) or withdrew. relatedId = help_request_id.
        // Resolve job_id via fetch, then push to the lobby. Fallback to home.
        if (notification.relatedId == null) break;
        final helpRequestWithdrew = await ref
            .read(helpRequestRepositoryProvider)
            .fetchHelpRequestById(notification.relatedId!);
        if (!context.mounted) break;
        if (helpRequestWithdrew != null) {
          context.push(
            '/worker/job/${helpRequestWithdrew.jobId}/help-requests',
          );
        } else {
          context.go('/worker/home');
        }
    }
  }
}
