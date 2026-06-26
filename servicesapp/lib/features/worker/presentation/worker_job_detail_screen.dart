import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/error_utils.dart';
import '../../auth/application/auth_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';
import '../application/worker_providers.dart';
import '../../../core/widgets/photo_viewer_screen.dart';

class WorkerJobDetailScreen extends ConsumerStatefulWidget {
  final JobRequest job;

  const WorkerJobDetailScreen({super.key, required this.job});

  @override
  ConsumerState<WorkerJobDetailScreen> createState() =>
      _WorkerJobDetailScreenState();
}

class _WorkerJobDetailScreenState extends ConsumerState<WorkerJobDetailScreen> {
  Future<void> _showProposalSheet() async {
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final success = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProposalSheet(job: widget.job),
    );
    if (success != true) return;
    ref.invalidate(jobsInRadiusProvider);
    scaffold.showSnackBar(
      const SnackBar(content: Text('Proposta enviada!')),
    );
    router.go('/worker/home');
  }

  String? _sizeLabel() => switch (widget.job.sizeEstimate) {
        SizeEstimate.small => 'Pequeno',
        SizeEstimate.medium => 'Médio',
        SizeEstimate.large => 'Grande',
        null => null,
      };

  String _dateModeShortLabel() => switch (widget.job.dateMode) {
        DateMode.fixed when widget.job.preferredDate != null =>
          'Data: ${DateFormat('dd/MM/yyyy').format(widget.job.preferredDate!)}',
        DateMode.fixed => 'Data não definida',
        DateMode.flexible => 'Cliente flexível quanto à data',
        DateMode.availability => 'Por disponibilidade',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serviceTypesAsync = ref.watch(serviceTypesProvider);
    final workerAsync = ref.watch(workerProfileProvider);
    final photosAsync = ref.watch(jobPhotosProvider(widget.job.id));

    final currentUserId = ref.watch(currentUserIdProvider) ?? '';
    final workerProposalAsync = currentUserId.isEmpty
        ? const AsyncValue<JobProposal?>.data(null)
        : ref.watch(workerProposalForJobProvider((widget.job.id, currentUserId)));
    final isCheckingProposal = workerProposalAsync.isLoading;
    final alreadySent = workerProposalAsync.asData?.value != null;

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
                    label: _dateModeShortLabel()),
                if (distanceStr != null)
                  _DetailChip(
                      icon: Icons.place_outlined, label: distanceStr),
                if (sizeLabel != null)
                  _DetailChip(
                      icon: Icons.straighten_outlined, label: sizeLabel),
                if (widget.job.proposalCount > 0)
                  _DetailChip(
                    icon: Icons.people_outlined,
                    label:
                        '${widget.job.proposalCount} proposta${widget.job.proposalCount > 1 ? 's' : ''}',
                  ),
              ],
            ),
            // Availability text shown separately (can be long)
            if (widget.job.dateMode == DateMode.availability &&
                widget.job.availabilityText != null &&
                widget.job.availabilityText!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.event_note_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Disponibilidade do cliente:',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        Text(widget.job.availabilityText!,
                            style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ],
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
            if (alreadySent) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline,
                      color: Colors.blue.shade700, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                        'Já enviaste uma proposta para este pedido.'),
                  ),
                ]),
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
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PhotoViewerScreen(
                                photoUrls: photos,
                                initialIndex: i,
                              ),
                            ),
                          ),
                          child: ClipRRect(
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
                    ),
                  ],
                );
              },
            ),
            SizedBox(height: alreadySent ? 32 : 80),
          ],
        ),
      ),
      bottomNavigationBar: alreadySent
          ? null
          : Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: isCheckingProposal ? null : _showProposalSheet,
                child: isCheckingProposal
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Enviar proposta'),
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

  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  bool _scheduledFlexible = false;

  @override
  void initState() {
    super.initState();
    _peopleController.text = '1';
    final profile = ref.read(workerProfileProvider).value;
    if (profile?.defaultHourlyRate != null && profile!.defaultHourlyRate! > 0) {
      _rateController.text = profile.defaultHourlyRate!.toStringAsFixed(2);
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

  Future<void> _pickScheduledDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _scheduledDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _scheduledDate = picked);
  }

  Future<void> _pickScheduledTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => _scheduledTime = picked);
  }

  String _formatScheduledDate() {
    if (_scheduledDate == null) return 'Data do trabalho';
    return DateFormat('dd/MM/yyyy').format(_scheduledDate!);
  }

  String _formatScheduledTime() {
    if (_scheduledTime == null) return 'Hora de início';
    return '${_scheduledTime!.hour.toString().padLeft(2, '0')}:'
        '${_scheduledTime!.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;

    if (_scheduledDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Define a data do trabalho.'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    if (!_scheduledFlexible && _scheduledTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Define a hora de início ou marca horário flexível.'),
        backgroundColor: Colors.red,
      ));
      return;
    }

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
            scheduledDate: _scheduledDate,
            scheduledTime: _scheduledTime != null ? _formatScheduledTime() : null,
            scheduledFlexible: _scheduledFlexible,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
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

                // ── Scheduling ─────────────────────────────────────────────
                Text('Agendamento', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickScheduledDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(_formatScheduledDate()),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _scheduledFlexible,
                  onChanged: (v) => setState(() {
                    _scheduledFlexible = v;
                    if (v) _scheduledTime = null;
                  }),
                  title: const Text('Horário flexível neste dia'),
                  contentPadding: EdgeInsets.zero,
                ),
                if (!_scheduledFlexible) ...[
                  OutlinedButton.icon(
                    onPressed: _pickScheduledTime,
                    icon: const Icon(Icons.access_time_outlined),
                    label: Text(_formatScheduledTime()),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 16),

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
