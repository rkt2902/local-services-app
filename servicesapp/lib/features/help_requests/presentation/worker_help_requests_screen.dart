import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/error_utils.dart';
import '../../worker/application/worker_providers.dart';
import '../../ratings/application/rating_providers.dart';
import '../../ratings/presentation/rating_sheet.dart';
import '../application/help_request_providers.dart';
import '../data/help_request_model.dart';

// ─── Root screen ─────────────────────────────────────────────────────────────

class WorkerHelpRequestsScreen extends ConsumerStatefulWidget {
  const WorkerHelpRequestsScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  ConsumerState<WorkerHelpRequestsScreen> createState() =>
      _WorkerHelpRequestsScreenState();
}

class _WorkerHelpRequestsScreenState
    extends ConsumerState<WorkerHelpRequestsScreen> {
  final Set<String> _appliedIds = {};
  final Map<String, bool> _broughtEquipment = {};
  final Map<String, bool> _applying = {};

  Future<void> _onDiscoverRefresh() async =>
      ref.invalidate(helpRequestSummariesInRadiusProvider);

  Future<void> _apply(HelpRequestSummary summary) async {
    final messenger = ScaffoldMessenger.of(context);
    final broughtEquipment =
        summary.equipmentRequired || (_broughtEquipment[summary.id] ?? false);
    setState(() => _applying[summary.id] = true);
    try {
      await ref.read(helpRequestRepositoryProvider).applyToHelpRequest(
            helpRequestId: summary.id,
            broughtEquipment: broughtEquipment,
          );
      if (!mounted) return;
      setState(() => _appliedIds.add(summary.id));
      ref.invalidate(helpRequestSummariesInRadiusProvider);
      messenger.showSnackBar(
          const SnackBar(content: Text('Candidatura enviada')));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _applying.remove(summary.id));
    }
  }

  Widget _buildDiscoverTab() {
    final summaryAsync = ref.watch(helpRequestSummariesInRadiusProvider);
    final workerProfile = ref.watch(workerProfileProvider).value;
    final serviceTypes = ref.watch(serviceTypesProvider).value ?? [];

    return summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(friendlyError(e)),
        ),
      ),
      data: (summaries) {
        if (summaries.isEmpty) {
          return LayoutBuilder(
            builder: (context, constraints) => RefreshIndicator(
              onRefresh: _onDiscoverRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.group_off, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'Não há pedidos de ajuda na tua zona.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _onDiscoverRefresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: summaries.length,
            itemBuilder: (context, index) {
              final s = summaries[index];
              final serviceTypeName = serviceTypes
                      .where((t) => t.id == s.serviceTypeId)
                      .firstOrNull
                      ?.name ??
                  '—';

              double? distanceMeters;
              if (workerProfile != null) {
                distanceMeters = Geolocator.distanceBetween(
                  workerProfile.baseLat,
                  workerProfile.baseLng,
                  s.locationLat,
                  s.locationLng,
                );
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _HelpRequestCard(
                  summary: s,
                  serviceTypeName: serviceTypeName,
                  distanceMeters: distanceMeters,
                  isApplied: _appliedIds.contains(s.id),
                  isApplying: _applying[s.id] == true,
                  broughtEquipment: _broughtEquipment[s.id] ?? false,
                  onBroughtEquipmentChanged: (v) =>
                      setState(() => _broughtEquipment[s.id] = v),
                  onApply: () => _apply(s),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pedidos de ajuda'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Descobrir'),
              Tab(text: 'As minhas candidaturas'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildDiscoverTab(),
            const _MyApplicationsTab(),
          ],
        ),
      ),
    );
  }
}

// ─── "As minhas candidaturas" tab ────────────────────────────────────────────

class _MyApplicationsTab extends ConsumerStatefulWidget {
  const _MyApplicationsTab();

  @override
  ConsumerState<_MyApplicationsTab> createState() => _MyApplicationsTabState();
}

class _MyApplicationsTabState extends ConsumerState<_MyApplicationsTab> {
  final Set<String> _withdrawing = {};

  Future<void> _onRefresh() async => ref.invalidate(myHelpAcceptancesProvider);

  Future<void> _withdraw(HelpAcceptanceSummary ha) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar desistência'),
        content: const Text(
          'Tens a certeza que queres desistir desta ajuda? '
          'O worker principal será notificado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desistir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _withdrawing.add(ha.id));
    try {
      await ref
          .read(helpRequestRepositoryProvider)
          .withdrawHelpAcceptance(ha.id);
      if (!mounted) return;
      ref.invalidate(myHelpAcceptancesProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Desististe desta ajuda.')),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _withdrawing.remove(ha.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myHelpAcceptancesProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(friendlyError(e)),
        ),
      ),
      data: (acceptances) {
        if (acceptances.isEmpty) {
          return LayoutBuilder(
            builder: (context, constraints) => RefreshIndicator(
              onRefresh: _onRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.group_off, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'Ainda não te candidataste a nenhum pedido de ajuda.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final pending = acceptances
            .where((a) => a.status == HelpAcceptanceStatus.pending)
            .toList();
        final accepted = acceptances
            .where((a) => a.status == HelpAcceptanceStatus.accepted)
            .toList();
        final history = acceptances
            .where((a) =>
                a.status == HelpAcceptanceStatus.rejected ||
                a.status == HelpAcceptanceStatus.cancelled)
            .toList();

        return RefreshIndicator(
          onRefresh: _onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (pending.isNotEmpty) ...[
                const _SectionHeader('Pendentes'),
                ...pending.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PendingCard(acceptance: a),
                  ),
                ),
              ],
              if (accepted.isNotEmpty) ...[
                if (pending.isNotEmpty) const SizedBox(height: 8),
                const _SectionHeader('Aceites'),
                ...accepted.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _AcceptedCard(
                      acceptance: a,
                      isWithdrawing: _withdrawing.contains(a.id),
                      onWithdraw: () => _withdraw(a),
                    ),
                  ),
                ),
              ],
              if (history.isNotEmpty) ...[
                if (pending.isNotEmpty || accepted.isNotEmpty)
                  const SizedBox(height: 8),
                const _SectionHeader('Histórico'),
                ...history.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _HistoryCard(acceptance: a),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

(String, Color) _jobStatusDisplay(String status) => switch (status) {
      'confirmed' => ('Confirmado', Colors.green.shade600),
      'awaiting_confirmation' =>
        ('A aguardar confirmação', Colors.orange.shade700),
      'completed' => ('Concluído', Colors.green.shade800),
      'cancelled' => ('Cancelado', Colors.red.shade400),
      _ => ('Em aberto', Colors.blue.shade600),
    };

// ─── Candidature cards ────────────────────────────────────────────────────────

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.acceptance});
  final HelpAcceptanceSummary acceptance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              acceptance.serviceTypeName,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            _Meta(
              icon: Icons.person_outline,
              label: 'Principal: ${acceptance.principalName}',
            ),
            if (acceptance.broughtEquipment) ...[
              const SizedBox(height: 4),
              _Meta(
                icon: Icons.build_outlined,
                label: 'Levo equipamento',
              ),
            ],
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                'À espera de decisão',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AcceptedCard extends ConsumerStatefulWidget {
  const _AcceptedCard({
    required this.acceptance,
    required this.isWithdrawing,
    required this.onWithdraw,
  });
  final HelpAcceptanceSummary acceptance;
  final bool isWithdrawing;
  final VoidCallback onWithdraw;

  @override
  ConsumerState<_AcceptedCard> createState() => _AcceptedCardState();
}

class _AcceptedCardState extends ConsumerState<_AcceptedCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (jobLabel, jobColor) =
        _jobStatusDisplay(widget.acceptance.jobStatus);
    final isCompleted = widget.acceptance.jobStatus == 'completed';
    final jobId = widget.acceptance.jobId;

    final ratingAsync = jobId.isNotEmpty
        ? ref.watch(myRatingForJobProvider(jobId))
        : const AsyncData<Rating?>(null);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.acceptance.serviceTypeName,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: jobColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    jobLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: jobColor, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _Meta(
              icon: Icons.person_outline,
              label: 'Principal: ${widget.acceptance.principalName}',
            ),
            if (widget.acceptance.agreedRate > 0) ...[
              const SizedBox(height: 4),
              _Meta(
                icon: Icons.euro_outlined,
                label:
                    '${widget.acceptance.agreedRate.toStringAsFixed(2).replaceAll('.', ',')} €/h acordado',
              ),
            ],
            const SizedBox(height: 12),
            if (isCompleted && jobId.isNotEmpty)
              ratingAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const SizedBox.shrink(),
                data: (existing) {
                  if (existing != null) {
                    return Row(children: [
                      Icon(Icons.check_circle,
                          color: theme.colorScheme.primary, size: 18),
                      const SizedBox(width: 8),
                      Text('Prestador avaliado',
                          style: theme.textTheme.bodySmall),
                      const Spacer(),
                      Row(
                        children: List.generate(
                          5,
                          (i) => Icon(
                            i < existing.stars
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 16,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ]);
                  }
                  return SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: _showHelperRatingSheet,
                      child: const Text('Avaliar o prestador'),
                    ),
                  );
                },
              )
            else if (!isCompleted)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: widget.isWithdrawing ? null : widget.onWithdraw,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                  ),
                  child: widget.isWithdrawing
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.error,
                          ),
                        )
                      : const Text('Desistir'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showHelperRatingSheet() async {
    final jobId = widget.acceptance.jobId;
    final submitted = await showRatingSheet(
      context: context,
      title: 'Avaliar o prestador principal',
      subtitle: widget.acceptance.principalName,
      onSubmit: (stars, comment) async {
        await ref.read(ratingRepositoryProvider).submitHelperRating(
              jobId: jobId,
              stars: stars,
              comment: comment,
            );
      },
    );
    if (submitted != true || !mounted) return;
    ref.invalidate(myRatingForJobProvider(jobId));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Avaliação enviada!')));
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.acceptance});
  final HelpAcceptanceSummary acceptance;

  String get _statusLabel => switch (acceptance.status) {
        HelpAcceptanceStatus.rejected => 'Não selecionado',
        HelpAcceptanceStatus.cancelled => 'Desististe',
        _ => '—',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    acceptance.serviceTypeName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Principal: ${acceptance.principalName}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _statusLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Discover tab widgets (unchanged) ────────────────────────────────────────

class _HelpRequestCard extends StatelessWidget {
  const _HelpRequestCard({
    required this.summary,
    required this.serviceTypeName,
    this.distanceMeters,
    required this.isApplied,
    required this.isApplying,
    required this.broughtEquipment,
    required this.onBroughtEquipmentChanged,
    required this.onApply,
  });

  final HelpRequestSummary summary;
  final String serviceTypeName;
  final double? distanceMeters;
  final bool isApplied;
  final bool isApplying;
  final bool broughtEquipment;
  final ValueChanged<bool> onBroughtEquipmentChanged;
  final VoidCallback onApply;

  String? _distanceStr() {
    if (distanceMeters == null) return null;
    return distanceMeters! < 1000
        ? '${distanceMeters!.round()} m'
        : '${(distanceMeters! / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distStr = _distanceStr();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    serviceTypeName,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${summary.slotsNeeded} vaga${summary.slotsNeeded == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (distStr != null)
                  _Meta(icon: Icons.place_outlined, label: distStr),
                _Meta(
                  icon: Icons.person_outline,
                  label: 'Com: ${summary.principalName}',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (summary.equipmentRequired)
              Row(children: [
                Icon(Icons.build, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Equipamento obrigatório',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ])
            else
              Row(children: [
                Checkbox(
                  value: broughtEquipment,
                  onChanged: isApplied
                      ? null
                      : (v) => onBroughtEquipmentChanged(v ?? false),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const Text('Levo o meu equipamento'),
              ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: isApplied || isApplying ? null : onApply,
                child: isApplying
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(isApplied ? 'Já candidatado' : 'Candidatar-me'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
