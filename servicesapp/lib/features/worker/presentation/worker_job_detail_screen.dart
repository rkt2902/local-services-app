import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../auth/application/auth_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../../proposals/application/proposal_providers.dart';
import '../application/worker_providers.dart';

class WorkerJobDetailScreen extends ConsumerStatefulWidget {
  final JobRequest job;

  const WorkerJobDetailScreen({super.key, required this.job});

  @override
  ConsumerState<WorkerJobDetailScreen> createState() =>
      _WorkerJobDetailScreenState();
}

class _WorkerJobDetailScreenState extends ConsumerState<WorkerJobDetailScreen> {
  Future<void> _showProposalSheet() async {
    final success = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProposalSheet(job: widget.job),
    );
    if (!mounted || success != true) return;
    ref.invalidate(jobsInRadiusProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Proposta enviada!')),
    );
    context.go('/worker/home');
  }

  String _formatDate() {
    if (widget.job.preferredDate == null) return 'Flexível';
    return DateFormat('dd/MM/yyyy').format(widget.job.preferredDate!);
  }

  String? _sizeLabel() => switch (widget.job.sizeEstimate) {
        SizeEstimate.small => 'Pequeno',
        SizeEstimate.medium => 'Médio',
        SizeEstimate.large => 'Grande',
        null => null,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serviceTypesAsync = ref.watch(serviceTypesProvider);
    final workerAsync = ref.watch(workerProfileProvider);
    final photosAsync = ref.watch(jobPhotosProvider(widget.job.id));

    final serviceType = serviceTypesAsync.value
        ?.where((s) => s.id == widget.job.serviceTypeId)
        .firstOrNull;

    final workerProfile = workerAsync.value;
    String? distanceStr;
    if (workerProfile != null) {
      final meters = Geolocator.distanceBetween(
        workerProfile.baseLat,
        workerProfile.baseLng,
        widget.job.locationLat,
        widget.job.locationLng,
      );
      distanceStr = meters < 1000
          ? '${meters.round()} m'
          : '${(meters / 1000).toStringAsFixed(1)} km';
    }

    final sizeLabel = _sizeLabel();

    return Scaffold(
      appBar: AppBar(
        title: Text(serviceType?.name ?? 'Detalhe do pedido'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    serviceType?.name ?? '',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (widget.job.urgency == Urgency.urgent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Urgente',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _DetailChip(
                    icon: Icons.calendar_today_outlined,
                    label: _formatDate()),
                if (distanceStr != null)
                  _DetailChip(
                      icon: Icons.place_outlined, label: distanceStr),
                if (sizeLabel != null)
                  _DetailChip(
                      icon: Icons.straighten_outlined, label: sizeLabel),
              ],
            ),
            if (widget.job.addressText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.job.addressText,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Text('Descrição', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(widget.job.description,
                style: theme.textTheme.bodyMedium),
            photosAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (photos) {
                if (photos.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    Text('Fotos', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: photos.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: 8),
                        itemBuilder: (_, i) => ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            photos[i],
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _showProposalSheet,
          child: const Text('Enviar proposta'),
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      );
}

class _ProposalSheet extends ConsumerStatefulWidget {
  final JobRequest job;

  const _ProposalSheet({required this.job});

  @override
  ConsumerState<_ProposalSheet> createState() => _ProposalSheetState();
}

class _ProposalSheetState extends ConsumerState<_ProposalSheet> {
  final _formKey = GlobalKey<FormState>();
  final _rateController = TextEditingController();
  final _hoursMinController = TextEditingController();
  final _hoursMaxController = TextEditingController();
  final _peopleController = TextEditingController();
  final _notesController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _peopleController.text = '1';
    final profile = ref.read(workerProfileProvider).value;
    if (profile?.defaultHourlyRate != null) {
      _rateController.text =
          profile!.defaultHourlyRate!.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _rateController.dispose();
    _hoursMinController.dispose();
    _hoursMaxController.dispose();
    _peopleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _submitting = true);
    try {
      await ref.read(proposalRepositoryProvider).createProposal(
            jobId: widget.job.id,
            workerId: user.id,
            hourlyRate: double.parse(_rateController.text.trim()),
            estimatedHoursMin:
                double.tryParse(_hoursMinController.text.trim()),
            estimatedHoursMax:
                double.tryParse(_hoursMaxController.text.trim()),
            peopleNeeded: int.parse(_peopleController.text.trim()),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Enviar proposta', style: theme.textTheme.titleLarge),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _rateController,
                  decoration: const InputDecoration(
                    labelText: 'Preço/hora (€)',
                    prefixIcon: Icon(Icons.euro_outlined),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Obrigatório.';
                    final n = double.tryParse(v.trim());
                    if (n == null || n <= 0) return 'Valor inválido.';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _hoursMinController,
                  decoration: const InputDecoration(
                    labelText: 'Horas mínimas',
                    prefixIcon: Icon(Icons.schedule_outlined),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Obrigatório.';
                    final n = double.tryParse(v.trim());
                    if (n == null || n <= 0) return 'Valor inválido.';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _hoursMaxController,
                  decoration: const InputDecoration(
                    labelText: 'Horas máximas',
                    prefixIcon: Icon(Icons.schedule_outlined),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Obrigatório.';
                    final n = double.tryParse(v.trim());
                    if (n == null || n <= 0) return 'Valor inválido.';
                    final minVal =
                        double.tryParse(_hoursMinController.text.trim()) ?? 0;
                    if (n < minVal) return 'Deve ser ≥ horas mínimas.';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _peopleController,
                  decoration: const InputDecoration(
                    labelText: 'Pessoas necessárias',
                    prefixIcon: Icon(Icons.group_outlined),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Obrigatório.';
                    final n = int.tryParse(v.trim());
                    if (n == null || n < 1) return 'Mínimo 1 pessoa.';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notas (opcional)',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Confirmar proposta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
