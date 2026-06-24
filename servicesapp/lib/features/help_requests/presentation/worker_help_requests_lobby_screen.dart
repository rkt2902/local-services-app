import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/error_utils.dart';
import '../../jobs/data/job_model.dart';
import '../../proposals/data/proposal_model.dart';
import '../../worker/application/worker_providers.dart';
import '../application/help_request_providers.dart';
import '../data/help_request_model.dart';

// ── View model ─────────────────────────────────────────────────────────────────

class _SlotVM {
  const _SlotVM({
    required this.helpRequest,
    this.acceptance,
    this.isOverflow = false,
  });
  final HelpRequest helpRequest;
  final HelpAcceptance? acceptance;
  final bool isOverflow; // pending beyond slots_needed — informational only
}

// ── Pure helpers ───────────────────────────────────────────────────────────────

List<_SlotVM> _buildSlots(
  List<HelpRequest> helpRequests,
  Map<String, List<HelpAcceptance>> candidatesByHr,
) {
  final slots = <_SlotVM>[];
  for (final hr in helpRequests) {
    final all = List<HelpAcceptance>.from(candidatesByHr[hr.id] ?? [])
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final accepted =
        all.where((c) => c.status == HelpAcceptanceStatus.accepted).toList();
    final pending =
        all.where((c) => c.status == HelpAcceptanceStatus.pending).toList();

    final filled = <_SlotVM>[];
    for (final a in accepted) {
      if (filled.length < hr.slotsNeeded) {
        filled.add(_SlotVM(helpRequest: hr, acceptance: a));
      }
    }
    for (final p in pending) {
      if (filled.length < hr.slotsNeeded) {
        filled.add(_SlotVM(helpRequest: hr, acceptance: p));
      } else {
        filled.add(_SlotVM(helpRequest: hr, acceptance: p, isOverflow: true));
      }
    }
    while (filled.length < hr.slotsNeeded) {
      filled.add(_SlotVM(helpRequest: hr));
    }
    slots.addAll(filled);
  }
  return slots;
}

double _suggestedRate(
    HelpRequest hr, HelpAcceptance candidate, JobProposal proposal) {
  if (hr.equipmentRequired) return proposal.hourlyRate;
  return candidate.broughtEquipment
      ? proposal.hourlyRate
      : proposal.hourlyRate * 0.7;
}

String _summaryCaption(List<_SlotVM> slots) {
  final accepted = slots
      .where((s) => s.acceptance?.status == HelpAcceptanceStatus.accepted)
      .length;
  final pending = slots
      .where((s) =>
          !s.isOverflow &&
          s.acceptance?.status == HelpAcceptanceStatus.pending)
      .length;
  final empty = slots
      .where((s) =>
          !s.isOverflow &&
          s.acceptance == null &&
          s.helpRequest.status != HelpRequestStatus.pendingApproval)
      .length;
  final locked = slots
      .where((s) =>
          !s.isOverflow &&
          s.helpRequest.status == HelpRequestStatus.pendingApproval)
      .length;
  final overflow = slots.where((s) => s.isOverflow).length;

  final parts = <String>[];
  if (accepted > 0) {
    parts.add('$accepted selecionad${accepted == 1 ? 'o' : 'os'}');
  }
  if (pending > 0) {
    parts.add('$pending candidato${pending == 1 ? '' : 's'} por decidir');
  }
  if (empty > 0) {
    parts.add('$empty vaga${empty == 1 ? '' : 's'} à espera de candidatos');
  }
  if (locked > 0) {
    parts.add(
        '$locked vaga${locked == 1 ? '' : 's'} à espera de aprovação do cliente');
  }
  if (overflow > 0) {
    parts.add(
        '$overflow candidatur${overflow == 1 ? 'a' : 'as'} excedente${overflow == 1 ? '' : 's'}');
  }
  return parts.isEmpty ? 'Sem vagas abertas' : parts.join(' · ');
}

// ── Screen ────────────────────────────────────────────────────────────────────

class WorkerHelpRequestsLobbyScreen extends ConsumerStatefulWidget {
  const WorkerHelpRequestsLobbyScreen({
    super.key,
    required this.job,
    required this.proposal,
  });

  final JobRequest job;
  final JobProposal proposal;

  @override
  ConsumerState<WorkerHelpRequestsLobbyScreen> createState() =>
      _WorkerHelpRequestsLobbyScreenState();
}

class _WorkerHelpRequestsLobbyScreenState
    extends ConsumerState<WorkerHelpRequestsLobbyScreen> {
  final Map<String, bool> _actingOn = {};

  Future<void> _showAcceptSheet(
    _SlotVM slot,
    String candidateName,
  ) async {
    final acceptance = slot.acceptance!;
    final suggested =
        _suggestedRate(slot.helpRequest, acceptance, widget.proposal);
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
                          final rate = double.tryParse(
                                controller.text.replaceAll(',', '.'),
                              ) ??
                              suggested;
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
      ref.invalidate(candidatesForHelpRequestProvider(slot.helpRequest.id));
      ref.invalidate(helpRequestsForJobProvider(widget.job.id));
    }
  }

  Future<void> _confirmReject(
    _SlotVM slot,
    String candidateName,
  ) async {
    final acceptance = slot.acceptance!;
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
      ref.invalidate(candidatesForHelpRequestProvider(slot.helpRequest.id));
      ref.invalidate(helpRequestsForJobProvider(widget.job.id));
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
    final helpRequestsAsync =
        ref.watch(helpRequestsForJobProvider(widget.job.id));
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

    final slots = _buildSlots(helpRequests, candidatesByHr);

    // Profile summaries — non-blocking; renders with initials while loading
    final profileSummaries = <String, Map<String, String?>>{};
    final seenWorkerIds = <String>{};
    for (final slot in slots) {
      final workerId = slot.acceptance?.workerId;
      if (workerId != null && seenWorkerIds.add(workerId)) {
        final sAsync = ref.watch(profileSummaryProvider(workerId));
        profileSummaries[workerId] = sAsync.asData?.value ?? {};
      }
    }

    if (anyLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Equipa')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (anyError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Equipa')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(friendlyError(anyError)),
          ),
        ),
      );
    }

    final workerProfile = workerAsync.asData?.value;
    final caption = _summaryCaption(slots);

    return Scaffold(
      appBar: AppBar(title: const Text('Equipa')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(helpRequestsForJobProvider(widget.job.id));
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
                jobId: widget.job.id,
              ),
            ),

            if (slots.isEmpty)
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
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Text('Vagas', style: theme.textTheme.titleMedium),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 20,
                    children: slots.map((slot) {
                      final workerId = slot.acceptance?.workerId;
                      final summary = workerId != null
                          ? (profileSummaries[workerId] ?? <String, String?>{})
                          : <String, String?>{};
                      final candidateName = summary['full_name'] ?? '—';
                      final candidateAvatarUrl = summary['avatar_url'];
                      final isActing =
                          _actingOn[slot.acceptance?.id] == true;

                      return _SlotCard(
                        slot: slot,
                        candidateName: candidateName,
                        candidateAvatarUrl: candidateAvatarUrl,
                        isActing: isActing,
                        proposal: widget.proposal,
                        onTapAccept: () =>
                            _showAcceptSheet(slot, candidateName),
                        onReject: () =>
                            _confirmReject(slot, candidateName),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: Text(
                  caption,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
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

// ── Slot card ─────────────────────────────────────────────────────────────────

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.slot,
    required this.candidateName,
    this.candidateAvatarUrl,
    required this.isActing,
    required this.proposal,
    required this.onTapAccept,
    required this.onReject,
  });

  final _SlotVM slot;
  final String candidateName;
  final String? candidateAvatarUrl;
  final bool isActing;
  final JobProposal proposal;
  final VoidCallback onTapAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hr = slot.helpRequest;
    final acceptance = slot.acceptance;

    final isLocked = hr.status == HelpRequestStatus.pendingApproval;
    final isPendingActionable =
        !slot.isOverflow && acceptance?.status == HelpAcceptanceStatus.pending;
    final isAccepted = acceptance?.status == HelpAcceptanceStatus.accepted;
    final isEmpty = acceptance == null && !isLocked;

    // Circle background color
    final Color circleColor;
    if (isActing || isLocked || isEmpty || slot.isOverflow) {
      circleColor = theme.colorScheme.surfaceContainerHighest;
    } else if (isAccepted) {
      circleColor = Colors.green.shade100;
    } else {
      circleColor = Colors.orange.shade100;
    }

    // Circle content
    final Widget circleContent;
    if (isActing) {
      circleContent = Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary),
        ),
      );
    } else if (isLocked) {
      circleContent = Center(
        child: Icon(Icons.lock_outline,
            size: 26,
            color: theme.colorScheme.onSurfaceVariant
                .withValues(alpha: 0.5)),
      );
    } else if (isEmpty) {
      circleContent = Center(
        child: Icon(Icons.person_outline,
            size: 26,
            color: theme.colorScheme.onSurfaceVariant
                .withValues(alpha: 0.5)),
      );
    } else {
      final hasAvatar =
          candidateAvatarUrl != null && candidateAvatarUrl!.isNotEmpty;
      if (hasAvatar) {
        circleContent = Image.network(
          candidateAvatarUrl!,
          fit: BoxFit.cover,
          width: 60,
          height: 60,
        );
      } else {
        final initial = candidateName.isNotEmpty
            ? candidateName.trim()[0].toUpperCase()
            : '?';
        circleContent = Center(
          child: Text(
            initial,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isAccepted
                  ? Colors.green.shade700
                  : slot.isOverflow
                      ? theme.colorScheme.onSurfaceVariant
                      : Colors.orange.shade700,
            ),
          ),
        );
      }
    }

    // Caption
    final String caption;
    final Color captionColor;
    if (isLocked) {
      caption = 'Bloqueada';
      captionColor = theme.colorScheme.onSurfaceVariant;
    } else if (isEmpty) {
      caption = 'Disponível';
      captionColor = theme.colorScheme.onSurfaceVariant;
    } else if (slot.isOverflow) {
      caption = 'Preenchida';
      captionColor = theme.colorScheme.onSurfaceVariant;
    } else if (isAccepted) {
      final rate = acceptance!.agreedRate;
      caption = rate > 0
          ? '€${rate.toStringAsFixed(0)}/h'
          : candidateName.split(' ').first;
      captionColor = Colors.green.shade700;
    } else {
      caption = candidateName.split(' ').first;
      captionColor = theme.colorScheme.onSurface;
    }

    // 60×60 circle
    final circleWidget = Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: circleColor,
        border: (isEmpty || isLocked)
            ? Border.all(
                color: theme.colorScheme.outlineVariant, width: 1.5)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: circleContent,
    );

    // 68×68 stack: circle centred + optional badges
    // Equipment badge: bottom-right; reject button: top-right
    final circleStack = SizedBox(
      width: 68,
      height: 68,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 4, top: 4, child: circleWidget),
          if (hr.equipmentRequired)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary,
                ),
                child:
                    const Icon(Icons.build, size: 10, color: Colors.white),
              ),
            ),
          if (isPendingActionable && !isActing)
            Positioned(
              top: 0,
              right: 0,
              // Inner GestureDetector wins the gesture arena over the outer one
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onReject,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.error,
                  ),
                  child: const Icon(Icons.close,
                      size: 12, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        circleStack,
        const SizedBox(height: 6),
        SizedBox(
          width: 72,
          child: Text(
            caption,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: captionColor),
          ),
        ),
      ],
    );

    if (isPendingActionable && !isActing) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTapAccept,
        child: content,
      );
    }

    return SizedBox(width: 88, child: content);
  }
}
