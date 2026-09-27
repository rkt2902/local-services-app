import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/theme/app_status_presentation.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/address_map_link.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../../core/widgets/bottom_actions_bar.dart';
import '../../../core/widgets/photo_viewer_screen.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../../core/widgets/status_timeline.dart';
import '../../auth/application/auth_providers.dart';
import '../../help_requests/application/help_request_providers.dart';
import '../../help_requests/data/help_request_model.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../ratings/application/rating_providers.dart';
import '../../worker/application/worker_providers.dart';
import '../application/job_providers.dart';
import '../application/job_timeline.dart';
import '../data/job_model.dart';
import 'widgets/cancel_job_dialog.dart';
import 'widgets/reschedule_dialog.dart';

/// Ecrã dedicado ao pedido `confirmed` — extraído de
/// `client_job_detail_screen.dart` (doc.txt, "7b. Detalhe do pedido
/// agendado/confirmado"). `client_job_detail_screen.dart` delega para aqui
/// sem mudar de rota quando `job.status == JobStatus.confirmed`.
class ClientScheduledJobDetailScreen extends ConsumerStatefulWidget {
  const ClientScheduledJobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<ClientScheduledJobDetailScreen> createState() =>
      _ClientScheduledJobDetailScreenState();
}

class _ClientScheduledJobDetailScreenState
    extends ConsumerState<ClientScheduledJobDetailScreen> {
  bool _saving = false;
  bool _proposingReschedule = false;
  final Set<String> _approvingHelp = {};

  Future<void> _cancelJob() async {
    final result = await CancelJobDialog.show(context, isClient: true);
    if (result == null || !mounted) return;

    final wantsReopen = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Voltar a publicar?'),
        content: const Text(
            'Queres voltar a publicar este pedido para encontrar outro prestador?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    setState(() => _saving = true);
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    var navigatedAway = false;
    try {
      final newJobId = await ref.read(jobRepositoryProvider).cancelJob(
            jobId: widget.jobId,
            reason: result['reason']!,
            reasonDetail: result['reasonDetail'],
            clientWantsReopen: wantsReopen ?? false,
          );
      navigatedAway = true;
      router.go('/client/jobs');
      if (newJobId != null) {
        scaffold.showSnackBar(const SnackBar(
            content: Text('Pedido cancelado e reaberto para encontrar outro prestador.')));
      } else {
        scaffold.showSnackBar(const SnackBar(content: Text('Pedido cancelado.')));
      }
      ref.invalidate(clientJobsProvider);
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (!navigatedAway && mounted) setState(() => _saving = false);
    }
  }

  Future<void> _proposeReschedule() async {
    final result = await RescheduleDialog.show(context);
    if (result == null || !mounted) return;

    setState(() => _proposingReschedule = true);
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await ref.read(jobRepositoryProvider).proposeReschedule(
            jobId: widget.jobId,
            newDate: result['date'] as DateTime,
            newTime: result['time'] as String?,
            newFlexible: result['flexible'] as bool,
          );
      ref.invalidate(clientJobsProvider);
      ref.invalidate(jobByIdProvider(widget.jobId));
      scaffold.showSnackBar(const SnackBar(content: Text('Remarcação enviada.')));
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _proposingReschedule = false);
    }
  }

  Future<void> _acceptReschedule() async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await ref.read(jobRepositoryProvider).acceptReschedule(widget.jobId);
      ref.invalidate(clientJobsProvider);
      ref.invalidate(jobByIdProvider(widget.jobId));
      scaffold.showSnackBar(const SnackBar(content: Text('Nova data aceite.')));
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _rejectReschedule() async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await ref.read(jobRepositoryProvider).rejectReschedule(widget.jobId);
      ref.invalidate(clientJobsProvider);
      ref.invalidate(jobByIdProvider(widget.jobId));
      scaffold.showSnackBar(const SnackBar(content: Text('Remarcação recusada.')));
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _approveHelpRequest(String helpRequestId) async {
    setState(() => _approvingHelp.add(helpRequestId));
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await ref.read(helpRequestRepositoryProvider).approveHelpRequest(helpRequestId);
      ref.invalidate(helpRequestsForJobProvider(widget.jobId));
      scaffold.showSnackBar(const SnackBar(
        content: Text('Equipa aprovada! O prestador pode agora procurar ajudantes.'),
      ));
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _approvingHelp.remove(helpRequestId));
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    final uri = Uri.parse('https://wa.me/$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ref.watch(jobByIdProvider(widget.jobId)).when(
      loading: () => Scaffold(
        backgroundColor: AppColors.background,
        body: _ScheduledLoading(onBack: () => context.pop()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        body: _ScheduledError(
          onBack: () => context.pop(),
          onRetry: () => ref.invalidate(jobByIdProvider(widget.jobId)),
        ),
      ),
      data: (job) {
        if (job == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: _ScheduledError(onBack: () => context.pop(), onRetry: null),
          );
        }

        final theme = Theme.of(context);
        final currentUserId = ref.watch(currentUserIdProvider);
        final acceptedProposalAsync = ref.watch(acceptedProposalForJobProvider(widget.jobId));
        final photosAsync = ref.watch(jobPhotosProvider(widget.jobId));
        final workerId = acceptedProposalAsync.asData?.value?.workerId ?? '';
        final workerInfoAsync = ref.watch(workerBasicInfoProvider(workerId));
        final ratingAsync = ref.watch(ratingSummaryProvider(workerId));
        final serviceTypes = ref.watch(serviceTypesProvider).asData?.value ?? const [];
        final pendingHelpRequests = (ref
                .watch(helpRequestsForJobProvider(widget.jobId))
                .asData
                ?.value ??
            const [])
            .where((hr) => hr.status == HelpRequestStatus.pendingApproval)
            .toList();

        final serviceLabel = serviceTypes
                .where((s) => s.id == job.serviceTypeId)
                .map((s) => s.name)
                .firstOrNull ??
            '—';
        final workerPhone = workerInfoAsync.asData?.value['phone'] ?? '';

        final canReschedule =
            !_proposingReschedule && job.rescheduleStatus != RescheduleStatus.pending;
        final within24h = job.confirmedDate != null &&
            job.confirmedDate!.difference(DateTime.now()).inHours < 24;
        final canCancel =
            !_saving && job.rescheduleStatus != RescheduleStatus.pending && !within24h;

        Widget? rescheduleIncomingBanner;
        if (job.rescheduleStatus == RescheduleStatus.pending &&
            job.rescheduleProposedBy != null &&
            job.rescheduleProposedBy != currentUserId) {
          final dateStr = job.rescheduleProposedDate != null
              ? DateFormat('dd/MM/yyyy').format(job.rescheduleProposedDate!)
              : '—';
          final timeStr = job.rescheduleProposedFlexible == true
              ? '(horário flexível)'
              : (job.rescheduleProposedTime != null ? 'às ${job.rescheduleProposedTime}' : '');
          rescheduleIncomingBanner = Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppStatusColor.waiting.background,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Icon(Icons.event_repeat, color: AppStatusColor.waiting.foreground, size: 20),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'O jardineiro propôs remarcar para $dateStr $timeStr'.trim(),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppStatusColor.waiting.foreground),
                    ),
                  ),
                ]),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _acceptReschedule,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.input),
                          ),
                        ),
                        child: const Text('Aceitar nova data'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _rejectReschedule,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.divider),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.input),
                          ),
                        ),
                        child: const Text('Recusar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        Widget? rescheduleOutgoingNotice;
        if (job.rescheduleStatus == RescheduleStatus.pending &&
            job.rescheduleProposedBy == currentUserId) {
          rescheduleOutgoingNotice = Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppStatusColor.waiting.background,
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
            child: Row(
              children: [
                Icon(Icons.hourglass_top, color: AppStatusColor.waiting.foreground, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Aguarda resposta à remarcação que propuseste.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppStatusColor.waiting.foreground),
                  ),
                ),
              ],
            ),
          );
        }

        final photosWidget = photosAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => const SizedBox.shrink(),
          data: (urls) {
            if (urls.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fotos',
                    style: theme.textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: urls.length,
                      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PhotoViewerScreen(photoUrls: urls, initialIndex: i),
                        )),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                          child: Image.network(urls[i], width: 72, height: 72, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );

        final proposal = acceptedProposalAsync.asData?.value;
        final priceLabel = proposal != null && proposal.hourlyRate > 0
            ? '${proposal.hourlyRate.toStringAsFixed(2)} €/hora'
            : 'A combinar';

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              children: [
                _ScheduledHeader(
                  title: 'Pedido #${widget.jobId.substring(0, 8)}',
                  presentation: job.status.presentation(),
                  onBack: () => context.pop(),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.lg,
                    ),
                    children: [
                      if (job.reopenedFrom != null) ...[
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(AppRadius.input),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  'Este pedido foi criado automaticamente após o cancelamento '
                                  'de um pedido anterior.',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: AppColors.primaryPressed),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (rescheduleIncomingBanner != null) ...[
                        rescheduleIncomingBanner,
                        const SizedBox(height: AppSpacing.md),
                      ],
                      AppStaggeredEntrance(
                        index: 0,
                        child: _TimelineCard(
                          timeline: StatusTimeline(steps: buildJobTimeline(job)),
                          supportingLabel: _timelineSupportingLabel(job),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppStaggeredEntrance(
                        index: 1,
                        child: _WorkerContactCard(
                          workerInfoAsync: workerInfoAsync,
                          ratingAsync: ratingAsync,
                          onOpenWhatsApp: () => _openWhatsApp(workerPhone),
                        ),
                      ),
                      if (pendingHelpRequests.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        ...pendingHelpRequests.map((hr) => _PendingHelpRequestCard(
                              helpRequest: hr,
                              approving: _approvingHelp.contains(hr.id),
                              onApprove: () => _approveHelpRequest(hr.id),
                            )),
                      ],
                      if (rescheduleOutgoingNotice != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        rescheduleOutgoingNotice,
                      ],
                      const SizedBox(height: AppSpacing.md),
                      AppStaggeredEntrance(
                        index: 2,
                        child: _ScheduledSummary(
                          serviceLabel: serviceLabel,
                          dateTimeLabel: _scheduleLabel(job),
                          addressLabel: job.addressText.isNotEmpty
                              ? job.addressText
                              : 'Localização não especificada',
                          peopleLabel:
                              proposal != null && proposal.peopleNeeded > 1
                                  ? '${proposal.peopleNeeded} pessoas'
                                  : null,
                          priceLabel: priceLabel,
                        ),
                      ),
                      if (job.locationLat != 0 || job.locationLng != 0) ...[
                        const SizedBox(height: AppSpacing.sm),
                        AddressMapLink(
                          address: job.addressText,
                          lat: job.locationLat,
                          lng: job.locationLng,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      const Divider(height: 1, color: AppColors.divider),
                      const SizedBox(height: AppSpacing.md),
                      AppStaggeredEntrance(
                        index: 3,
                        child: _Description(description: job.description),
                      ),
                      photosWidget,
                    ],
                  ),
                ),
                BottomActionsBar(children: [
                  PrimaryActionButton(
                    label: 'Enviar mensagem',
                    onPressed: workerPhone.isEmpty ? null : () => _openWhatsApp(workerPhone),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: canReschedule ? _proposeReschedule : null,
                        child: Text(
                          'Remarcar',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: canReschedule
                                ? AppColors.primary
                                : AppStatusColor.neutral.foreground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      TextButton(
                        onPressed: canCancel ? _cancelJob : null,
                        child: Text(
                          'Cancelar pedido',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: canCancel
                                ? AppStatusColor.cancelled.foreground
                                : AppStatusColor.neutral.foreground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (within24h) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Cancelamento disponível até 24h antes da data confirmada.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _scheduleLabel(JobRequest job) {
  if (job.confirmedDate == null) return 'A combinar';
  final date = DateFormat('dd/MM/yyyy').format(job.confirmedDate!);
  if (job.confirmedFlexible) return '$date (horário flexível)';
  if (job.confirmedTime != null) return '$date às ${job.confirmedTime}';
  return date;
}

/// Substitui a legenda de apoio do timeline (obrigatória em doc.txt, ao
/// contrário do `_TimelineCard` de `client_job_detail_screen.dart` — lá só
/// existe para `open`). Deriva de `confirmedDate`, dado real, em vez de
/// inventar uma frase estática.
String _timelineSupportingLabel(JobRequest job) {
  if (job.confirmedDate == null) return 'Data a combinar com o profissional.';
  final date = DateFormat('dd/MM/yyyy').format(job.confirmedDate!);
  if (job.confirmedFlexible) return 'Serviço agendado para $date (horário flexível).';
  if (job.confirmedTime != null) return 'Serviço agendado para $date às ${job.confirmedTime}.';
  return 'Serviço agendado para $date.';
}

class _ScheduledHeader extends StatelessWidget {
  const _ScheduledHeader({required this.title, required this.presentation, required this.onBack});

  final String title;
  final AppStatusPresentation presentation;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(title, style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary)),
          ),
          AppStatusBadge.fromPresentation(presentation: presentation),
        ],
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.timeline, required this.supportingLabel});

  final Widget timeline;
  final String supportingLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          timeline,
          const SizedBox(height: AppSpacing.sm),
          Text(
            supportingLabel,
            textAlign: TextAlign.center,
            style: textTheme.labelMedium?.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

class _WorkerContactCard extends StatelessWidget {
  const _WorkerContactCard({
    required this.workerInfoAsync,
    required this.ratingAsync,
    required this.onOpenWhatsApp,
  });

  final AsyncValue<Map<String, String>> workerInfoAsync;
  final AsyncValue<RatingSummary> ratingAsync;
  final VoidCallback onOpenWhatsApp;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return workerInfoAsync.when(
      loading: () => AppSkeletonShimmer(
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
        ),
      ),
      error: (e, _) => const Text('Não foi possível carregar o contacto.'),
      data: (info) {
        final name = info['full_name'] ?? '';
        final phone = info['phone'] ?? '';
        final avatarUrl = info['avatar_url'];
        final rating = ratingAsync.asData?.value;
        final ratingLabel = rating != null && rating.ratingCount > 0
            ? '★ ${rating.avgRating.toStringAsFixed(1)} (${rating.ratingCount})'
            : 'Sem avaliações ainda';

        return Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primaryContainer,
              backgroundImage:
                  (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
              child: (avatarUrl == null || avatarUrl.isEmpty)
                  ? const Icon(Icons.person_outline_rounded, color: AppColors.primary)
                  : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? '—' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
                  ),
                  Text(ratingLabel, style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              onPressed: phone.isEmpty ? null : onOpenWhatsApp,
              tooltip: 'WhatsApp',
              icon: const Icon(Icons.chat_outlined, color: AppColors.primary),
            ),
          ],
        );
      },
    );
  }
}

class _PendingHelpRequestCard extends StatelessWidget {
  const _PendingHelpRequestCard({
    required this.helpRequest,
    required this.approving,
    required this.onApprove,
  });

  final HelpRequest helpRequest;
  final bool approving;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppStatusColor.waiting.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.group_add_outlined, color: AppStatusColor.waiting.foreground, size: 20),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'O prestador pediu ajuda extra para este trabalho',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: AppStatusColor.waiting.foreground),
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${helpRequest.slotsNeeded} '
            'ajudante${helpRequest.slotsNeeded == 1 ? '' : 's'}'
            '${helpRequest.equipmentRequired ? ' · Equipamento exigido' : ''}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppStatusColor.waiting.foreground),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: approving ? null : onApprove,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.input)),
            ),
            child: approving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface),
                  )
                : const Text('Aprovar equipa'),
          ),
        ],
      ),
    );
  }
}

class _ScheduledSummary extends StatelessWidget {
  const _ScheduledSummary({
    required this.serviceLabel,
    required this.dateTimeLabel,
    required this.addressLabel,
    required this.priceLabel,
    this.peopleLabel,
  });

  final String serviceLabel;
  final String dateTimeLabel;
  final String addressLabel;
  final String priceLabel;
  final String? peopleLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _SummaryRow(label: 'Serviço', value: serviceLabel),
          const SizedBox(height: AppSpacing.sm),
          _SummaryRow(label: 'Data e hora', value: dateTimeLabel),
          const SizedBox(height: AppSpacing.sm),
          _SummaryRow(label: 'Morada', value: addressLabel),
          if (peopleLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _SummaryRow(label: 'Equipa', value: peopleLabel!),
          ],
          const SizedBox(height: AppSpacing.sm),
          const Divider(color: AppColors.divider),
          const SizedBox(height: AppSpacing.sm),
          _SummaryRow(label: 'Valor acordado', value: priceLabel, emphasized: true),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.emphasized = false});

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
        ),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: textTheme.bodyMedium?.copyWith(
              color: emphasized ? AppColors.primary : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _Description extends StatelessWidget {
  const _Description({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Descrição', style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.xs),
        Text(description, style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary)),
      ],
    );
  }
}

class _ScheduledLoading extends StatelessWidget {
  const _ScheduledLoading({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _LoadingHeader(onBack: onBack),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, index) => AppSkeletonShimmer(
                child: Container(
                  height: index == 0 ? 88 : 76,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingHeader extends StatelessWidget {
  const _LoadingHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: AppSkeletonShimmer(
              child: Container(
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduledError extends StatelessWidget {
  const _ScheduledError({required this.onBack, required this.onRetry});

  final VoidCallback onBack;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Column(
        children: [
          _LoadingHeader(onBack: onBack),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Não foi possível carregar o pedido.',
                      textAlign: TextAlign.center,
                      style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton(onPressed: onRetry, child: const Text('Tentar novamente')),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
