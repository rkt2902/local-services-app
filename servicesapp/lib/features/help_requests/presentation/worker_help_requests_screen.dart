import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/utils/error_utils.dart';
import '../../worker/application/worker_providers.dart';
import '../application/help_request_providers.dart';
import '../data/help_request_model.dart';

class WorkerHelpRequestsScreen extends ConsumerStatefulWidget {
  const WorkerHelpRequestsScreen({super.key});

  @override
  ConsumerState<WorkerHelpRequestsScreen> createState() =>
      _WorkerHelpRequestsScreenState();
}

class _WorkerHelpRequestsScreenState
    extends ConsumerState<WorkerHelpRequestsScreen> {
  final Set<String> _appliedIds = {};
  final Map<String, bool> _broughtEquipment = {};
  final Map<String, bool> _applying = {};

  Future<void> _onRefresh() async =>
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

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(helpRequestSummariesInRadiusProvider);
    final workerProfile = ref.watch(workerProfileProvider).value;
    final serviceTypes = ref.watch(serviceTypesProvider).value ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Pedidos de ajuda')),
      body: summaryAsync.when(
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
            onRefresh: _onRefresh,
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
      ),
    );
  }
}

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
