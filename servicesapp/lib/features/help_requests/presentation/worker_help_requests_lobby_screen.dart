import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';
import '../../ratings/application/rating_providers.dart';
import '../../ratings/presentation/ratings_sheet.dart';
import '../../worker/application/worker_providers.dart';
import '../application/help_request_providers.dart';
import '../data/help_request_model.dart';

// ── Pure helper ────────────────────────────────────────────────────────────────

double _suggestedRate(
    HelpRequest hr, HelpAcceptance candidate, JobProposal? proposal) {
  final rate = proposal?.hourlyRate ?? 0;
  if (hr.equipmentRequired) return rate;
  return candidate.broughtEquipment ? rate : rate * 0.7;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class WorkerHelpRequestsLobbyScreen extends ConsumerStatefulWidget {
  const WorkerHelpRequestsLobbyScreen({
    super.key,
    required this.jobId,
  });

  final String jobId;

  @override
  ConsumerState<WorkerHelpRequestsLobbyScreen> createState() =>
      _WorkerHelpRequestsLobbyScreenState();
}

class _WorkerHelpRequestsLobbyScreenState
    extends ConsumerState<WorkerHelpRequestsLobbyScreen> {
  final Map<String, bool> _actingOn = {};

  Future<void> _showAcceptSheet(
    HelpRequest hr,
    HelpAcceptance acceptance,
    String candidateName,
    JobProposal? proposal,
  ) async {
    final suggested = _suggestedRate(hr, acceptance, proposal);
    final controller =
        TextEditingController(text: suggested.toStringAsFixed(2));
    bool submitting = false;
    final scaffold = ScaffoldMessenger.of(context);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Aceitar candidato',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(candidateName,
                    style: Theme.of(ctx).textTheme.bodyLarge),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(
                    acceptance.broughtEquipment
                        ? Icons.build_outlined
                        : Icons.person_outline,
                    size: 16,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    acceptance.broughtEquipment
                        ? 'Traz equipamento'
                        : 'Sem equipamento',
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                ]),
                const SizedBox(height: 20),
                TextFormField(
                  controller: controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Taxa acordada (€/hora)',
                    prefixText: '€ ',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Taxa sugerida: €${suggested.toStringAsFixed(2)}/hora',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          final parsed = double.tryParse(
                            controller.text.replaceAll(',', '.'),
                          );
                          if (parsed != null && parsed <= 0) {
                            scaffold.showSnackBar(const SnackBar(
                              content: Text('A taxa deve ser maior que zero.'),
                            ));
                            return;
                          }
                          final rate = parsed ?? suggested;
                          setSheetState(() => submitting = true);
                          try {
                            await ref
                                .read(helpRequestRepositoryProvider)
                                .acceptCandidate(
                                  helpAcceptanceId: acceptance.id,
                                  agreedRate: rate,
                                );
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (e) {
                            setSheetState(() => submitting = false);
                            scaffold.showSnackBar(SnackBar(
                              content: Text(friendlyError(e)),
                              backgroundColor: Colors.red,
                            ));
                          }
                        },
                  child: submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Confirmar'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    controller.dispose();
    if (confirmed == true) {
      ref.invalidate(candidatesForHelpRequestProvider(hr.id));
      ref.invalidate(helpRequestsForJobProvider(widget.jobId));
    }
  }

  Future<void> _confirmReject(
    HelpRequest hr,
    HelpAcceptance acceptance,
    String candidateName,
  ) async {
    final scaffold = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Recusar candidato?'),
        content: Text('Tens a certeza que queres recusar $candidateName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Voltar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogCtx).colorScheme.error),
            child: const Text('Recusar'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _actingOn[acceptance.id] = true);
    try {
      await ref
          .read(helpRequestRepositoryProvider)
          .rejectHelpCandidate(acceptance.id);
      ref.invalidate(candidatesForHelpRequestProvider(hr.id));
      ref.invalidate(helpRequestsForJobProvider(widget.jobId));
    } catch (e) {
      if (mounted) {
        scaffold.showSnackBar(SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _actingOn.remove(acceptance.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workerAsync = ref.watch(workerProfileProvider);
    final proposalAsync = ref.watch(acceptedProposalForJobProvider(widget.jobId));
    final proposal = proposalAsync.asData?.value;
    final helpRequestsAsync =
        ref.watch(helpRequestsForJobProvider(widget.jobId));
    final helpRequests = helpRequestsAsync.asData?.value ?? [];

    var anyLoading = helpRequestsAsync.isLoading;
    Object? anyError =
        helpRequestsAsync.hasError ? helpRequestsAsync.error : null;
    final candidatesByHr = <String, List<HelpAcceptance>>{};

    for (final hr in helpRequests) {
      final cAsync = ref.watch(candidatesForHelpRequestProvider(hr.id));
      if (cAsync.isLoading) anyLoading = true;
      if (cAsync.hasError) anyError ??= cAsync.error;
      candidatesByHr[hr.id] = cAsync.asData?.value ?? [];
    }

    if (anyLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Equipa')),
        body: const SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    if (anyError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Equipa')),
        body: SafeArea(child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(friendlyError(anyError)),
          ),
        )),
      );
    }

    final workerProfile = workerAsync.asData?.value;

    // Build per-HR section widgets
    final sectionWidgets = <Widget>[];
    for (final hr in helpRequests) {
      final all = List<HelpAcceptance>.from(candidatesByHr[hr.id] ?? [])
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final accepted =
          all.where((c) => c.status == HelpAcceptanceStatus.accepted).toList();
      final pending =
          all.where((c) => c.status == HelpAcceptanceStatus.pending).toList();
      // Defensive client-side guard: if accepted_count >= slots_needed the
      // backend (migration 0017) will have already auto-rejected remaining
      // pending candidates. The guard prevents accept-button rendering in the
      // brief window between the action and the provider invalidation/refetch.
      final isFilled = accepted.length >= hr.slotsNeeded;

      sectionWidgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Slot count summary
            Text(
              '${accepted.length} de ${hr.slotsNeeded} '
              'vaga${hr.slotsNeeded == 1 ? '' : 's'} '
              'preenchida${hr.slotsNeeded == 1 ? '' : 's'}',
              style: theme.textTheme.titleMedium,
            ),

            if (hr.status == HelpRequestStatus.pendingApproval) ...[
              const SizedBox(height: 6),
              Text(
                'A aguardar aprovação do cliente.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],

            // Accepted candidates
            if (accepted.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Aceites',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              ...accepted.map((c) => _CandidateCard(
                    acceptance: c,
                    candidateName: c.fullName ?? 'Sem nome',
                    candidateAvatarUrl: c.avatarUrl,
                    isActing: _actingOn[c.id] == true,
                    isAccepted: true,
                    isActionable: false,
                    onAccept: null,
                    onReject: null,
                  )),
            ],

            // Pending candidates — all shown as individual actionable list items.
            // Any candidate with status = pending is acceptable as long as
            // accepted_count < slots_needed; arrival order does not matter.
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Por decidir',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              ...pending.map((c) {
                final isActing = _actingOn[c.id] == true;
                final isActionable = !isFilled && !isActing;
                final name = c.fullName ?? 'Sem nome';
                return _CandidateCard(
                  acceptance: c,
                  candidateName: name,
                  candidateAvatarUrl: c.avatarUrl,
                  isActing: isActing,
                  isAccepted: false,
                  isActionable: isActionable,
                  onAccept: isActionable
                      ? () => _showAcceptSheet(hr, c, name, proposal)
                      : null,
                  // Reject remains available regardless of slot status.
                  onReject: !isActing ? () => _confirmReject(hr, c, name) : null,
                );
              }),
            ],

            if (accepted.isEmpty && pending.isEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Sem candidatos ainda.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Equipa')),
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(helpRequestsForJobProvider(widget.jobId));
          for (final hr in helpRequests) {
            ref.invalidate(candidatesForHelpRequestProvider(hr.id));
          }
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _PrincipalHeader(
                avatarUrl: workerProfile?.avatarUrl,
                name: workerProfile?.fullName ?? '',
                jobId: widget.jobId,
              ),
            ),

            if (helpRequests.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Nenhuma vaga de ajudante para este trabalho.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildListDelegate([
                  ...sectionWidgets,
                  const SizedBox(height: 40),
                ]),
              ),
          ],
        ),
      )),
    );
  }
}

// ── Principal header ───────────────────────────────────────────────────────────

class _PrincipalHeader extends StatelessWidget {
  const _PrincipalHeader({
    required this.avatarUrl,
    required this.name,
    required this.jobId,
  });

  final String? avatarUrl;
  final String name;
  final String jobId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAvatar = avatarUrl != null && avatarUrl!.isNotEmpty;
    final initials = name.isNotEmpty ? name.trim()[0].toUpperCase() : '?';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundImage: hasAvatar ? NetworkImage(avatarUrl!) : null,
                backgroundColor: theme.colorScheme.primary,
                child: hasAvatar
                    ? null
                    : Text(
                        initials,
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(color: Colors.white),
                      ),
              ),
              Positioned(
                bottom: -4,
                right: -4,
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.star, size: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            name.isNotEmpty ? name : 'Tu',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            'Responsável · Job #${jobId.length >= 8 ? jobId.substring(0, 8) : jobId}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── Candidate card ─────────────────────────────────────────────────────────────

class _CandidateCard extends ConsumerWidget {
  const _CandidateCard({
    required this.acceptance,
    required this.candidateName,
    this.candidateAvatarUrl,
    required this.isActing,
    required this.isAccepted,
    required this.isActionable,
    required this.onAccept,
    required this.onReject,
  });

  final HelpAcceptance acceptance;
  final String candidateName;
  final String? candidateAvatarUrl;
  final bool isActing;
  final bool isAccepted;
  final bool isActionable;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ratingSummary =
        ref.watch(ratingSummaryProvider(acceptance.workerId)).asData?.value;

    final hasAvatar =
        candidateAvatarUrl != null && candidateAvatarUrl!.isNotEmpty;
    final initial = candidateName.isNotEmpty
        ? candidateName.trim()[0].toUpperCase()
        : '?';

    final Color avatarBg = isActing
        ? theme.colorScheme.surfaceContainerHighest
        : acceptance.status.presentation.color.background;

    final Color avatarFg = acceptance.status.presentation.color.foreground;

    Widget avatar = CircleAvatar(
      radius: 22,
      backgroundColor: avatarBg,
      backgroundImage:
          hasAvatar && !isActing ? NetworkImage(candidateAvatarUrl!) : null,
      child: isActing
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: theme.colorScheme.primary),
            )
          : hasAvatar
              ? null
              : Text(
                  initial,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: avatarFg),
                ),
    );

    if (acceptance.broughtEquipment) {
      avatar = Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary,
              ),
              child: const Icon(Icons.build, size: 8, color: Colors.white),
            ),
          ),
        ],
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidateName,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (ratingSummary != null && ratingSummary.ratingCount > 0)
                    GestureDetector(
                      onTap: () => showRatingsSheet(
                        context,
                        workerId: acceptance.workerId,
                        workerName: candidateName,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 12, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(
                            ratingSummary.avgRating.toStringAsFixed(1),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    acceptance.broughtEquipment
                        ? 'Traz equipamento'
                        : 'Sem equipamento',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  AppStatusBadge.fromPresentation(
                    presentation: acceptance.status.presentation,
                  ),
                  if (isAccepted && acceptance.agreedRate > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '€${acceptance.agreedRate.toStringAsFixed(2)}/hora',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: AppStatusColor.success.foreground,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
            if (isAccepted)
              Icon(Icons.check_circle,
                  color: AppStatusColor.success.foreground, size: 22),
            if (!isAccepted && !isActing) ...[
              if (onAccept != null)
                TextButton(
                  onPressed: onAccept,
                  child: const Text('Aceitar'),
                ),
              if (onReject != null)
                IconButton(
                  onPressed: onReject,
                  icon: Icon(Icons.close,
                      color: theme.colorScheme.error, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
