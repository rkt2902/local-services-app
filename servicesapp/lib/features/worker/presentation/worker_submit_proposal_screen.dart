import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/error_utils.dart';
import '../../auth/application/auth_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../proposals/application/proposal_providers.dart';
import '../application/worker_providers.dart';
import 'widgets/worker_submit_proposal_view.dart' as view;

/// Mapeamento fixo de período do dia → hora gravada em `scheduled_time`.
/// Não existe conceito de "período" na BD — só time/flexible — por isso o
/// mapeamento é só do lado do formulário (ver relatório de integração).
const _timeSlots = [
  view.WorkerProposalTimeSlotViewData(id: 'morning', label: 'Manhã'),
  view.WorkerProposalTimeSlotViewData(id: 'afternoon', label: 'Tarde'),
  view.WorkerProposalTimeSlotViewData(id: 'evening', label: 'Fim do dia'),
];

const _timeSlotToScheduledTime = {
  'morning': '09:00',
  'afternoon': '14:00',
  'evening': '18:00',
};

const _durationOptions = [
  view.WorkerProposalDurationViewData(
      id: '1-2h', label: '1-2h', minimumHours: 1, maximumHours: 2),
  view.WorkerProposalDurationViewData(
      id: '2-4h', label: '2-4h', minimumHours: 2, maximumHours: 4),
  view.WorkerProposalDurationViewData(
      id: '4-6h', label: '4-6h', minimumHours: 4, maximumHours: 6),
  view.WorkerProposalDurationViewData(
      id: '+6h', label: '+6h', minimumHours: 6, maximumHours: null),
];

/// Ecrã "Enviar proposta" — rota própria, substitui o antigo `_ProposalSheet`
/// (bottom sheet) de `worker_job_detail_screen.dart`.
class WorkerSubmitProposalScreen extends ConsumerStatefulWidget {
  const WorkerSubmitProposalScreen({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<WorkerSubmitProposalScreen> createState() =>
      _WorkerSubmitProposalScreenState();
}

class _WorkerSubmitProposalScreenState
    extends ConsumerState<WorkerSubmitProposalScreen> {
  bool _submitting = false;

  Future<view.WorkerProposalDateSelection?> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return null;
    return view.WorkerProposalDateSelection(
      value: picked,
      label: DateFormat('dd/MM/yyyy').format(picked),
    );
  }

  Future<void> _submit(view.WorkerProposalDraft draft) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    setState(() => _submitting = true);
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    // "Quantos ajudantes?" conta só os ajudantes — people_needed inclui o
    // próprio worker (ver relatório: mapeamento people_needed = helperCount + 1,
    // consistente com accept_proposal's slots_needed = people_needed - 1).
    final peopleNeeded = draft.needsHelpers ? draft.helperCount + 1 : 1;

    try {
      await ref.read(proposalRepositoryProvider).createProposal(
            jobId: widget.jobId,
            workerId: userId,
            hourlyRate: draft.hourlyPrice,
            estimatedHoursMin: draft.minimumEstimatedHours.toDouble(),
            estimatedHoursMax: draft.maximumEstimatedHours?.toDouble(),
            peopleNeeded: peopleNeeded,
            helpersEquipmentRequired: draft.helpersEquipmentRequired,
            notes: draft.message.trim().isEmpty ? null : draft.message.trim(),
            scheduledDate: draft.scheduledDate,
            scheduledTime: _timeSlotToScheduledTime[draft.timeSlotId],
            scheduledFlexible: false,
          );
      if (!mounted) return;
      router.pop();
      scaffold.showSnackBar(const SnackBar(content: Text('Proposta enviada!')));
      ref.invalidate(jobsInRadiusProvider);
      ref.invalidate(workerProposalForJobProvider);
    } catch (e) {
      if (!mounted) return;
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workerProfile = ref.watch(workerProfileProvider).asData?.value;
    final defaultRate = workerProfile?.defaultHourlyRate;

    final suggestedLabel = (defaultRate != null && defaultRate > 0)
        ? '€${defaultRate.toStringAsFixed(0)}/h'
        : 'sem valor de referência';

    return view.WorkerSubmitProposalScreen(
      suggestedHourlyPriceLabel: suggestedLabel,
      timeSlots: _timeSlots,
      durationOptions: _durationOptions,
      onBack: () => context.pop(),
      onSelectDate: _selectDate,
      onSubmit: _submit,
      initialHourlyPrice:
          (defaultRate != null && defaultRate > 0) ? defaultRate : null,
      isSubmitting: _submitting,
    );
  }
}
