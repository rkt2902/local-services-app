import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/price_labels.dart';
import '../../../core/widgets/app_date_picker.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../auth/application/auth_providers.dart';
import '../../../core/router/app_back_navigation.dart';
import '../../jobs/application/job_labels.dart';
import '../../jobs/application/job_providers.dart';
import '../../proposals/application/proposal_providers.dart';
import '../application/worker_list_invalidation.dart';
import '../application/worker_providers.dart';
import 'widgets/worker_submit_proposal_view.dart' as view;
import '../../../core/widgets/app_toast.dart';

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
      id: '1-2h', label: '1 a 2 h', minimum: 1, maximum: 2),
  view.WorkerProposalDurationViewData(
      id: '2-4h', label: '2 a 4 h', minimum: 2, maximum: 4),
  view.WorkerProposalDurationViewData(
      id: '4-6h', label: '4 a 6 h', minimum: 4, maximum: 6),
  view.WorkerProposalDurationViewData(
      id: '+6h', label: '+6 h', minimum: 6, maximum: null),
];

/// Duração em dias, só no valor total (design A6). "Mais de uma semana"
/// grava 8 dias sem máximo.
const _dayDurationOptions = [
  view.WorkerProposalDurationViewData(
      id: '1d', label: '1 dia', minimum: 1, maximum: 1),
  view.WorkerProposalDurationViewData(
      id: '2-3d', label: '2 a 3 dias', minimum: 2, maximum: 3),
  view.WorkerProposalDurationViewData(
      id: '4-7d', label: '4 a 7 dias', minimum: 4, maximum: 7),
  view.WorkerProposalDurationViewData(
      id: '+7d', label: 'Mais de uma semana', minimum: 8, maximum: null),
];

/// Validade do orçamento, em dias. A BD aceita até 60.
const _validityDays = [7, 15, 30];
const _defaultValidityDays = 15;

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
  String? _submitError;
  bool _jobClosed = false;

  /// Formato da última proposta do jardineiro; o formulário só abre depois
  /// de o saber, para não mudar de formato com o jardineiro a escrever.
  bool _lastModeLoaded = false;
  ProposalPricingMode? _lastMode;

  @override
  void initState() {
    super.initState();
    _loadLastMode();
  }

  Future<void> _loadLastMode() async {
    final userId = ref.read(currentUserIdProvider);
    final mode = userId == null
        ? null
        : await ref.read(proposalRepositoryProvider).fetchLastPricingMode(userId);
    if (!mounted) return;
    setState(() {
      _lastMode = mode;
      _lastModeLoaded = true;
    });
  }

  view.WorkerProposalValiditySelection _validity(int days) {
    final until = DateUtils.dateOnly(DateTime.now()).add(Duration(days: days));
    return view.WorkerProposalValiditySelection(
      days: days,
      label: '$days dias',
      untilLabel: 'até ${DateFormat('dd/MM').format(until)}',
    );
  }

  view.WorkerProposalDateSelection _dateSelection(DateTime date) {
    return view.WorkerProposalDateSelection(
      value: date,
      label: DateFormat('dd/MM/yyyy').format(date),
    );
  }

  Future<view.WorkerProposalDateSelection?> _selectDate(
      DateTime? current) async {
    // Só datas: a data do cliente vem à meia-noite e não pode ficar antes
    // do firstDate (o showDatePicker rebenta com um assert).
    final today = DateUtils.dateOnly(DateTime.now());
    final last = today.add(const Duration(days: 365));
    var initial = current ?? today.add(const Duration(days: 1));
    if (initial.isBefore(today)) initial = today;
    if (initial.isAfter(last)) initial = last;
    final picked = await showAppDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: last,
    );
    if (picked == null) return null;
    return _dateSelection(picked);
  }

  Future<view.WorkerProposalValiditySelection?> _selectValidity() {
    return AppSheet.show<view.WorkerProposalValiditySelection>(
      context,
      builder: (sheetContext) => AppSheet(
        title: 'Validade do orçamento',
        onClose: () => Navigator.of(sheetContext).pop(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final days in _validityDays)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '$days dias',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textPrimary),
                ),
                trailing: Text(
                  _validity(days).untilLabel,
                  style: Theme.of(sheetContext)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                onTap: () => Navigator.of(sheetContext).pop(_validity(days)),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(view.WorkerProposalDraft draft) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final toast = AppToast.of(context);
    final router = GoRouter.of(context);

    // "Quantos ajudantes?" conta só os ajudantes — people_needed inclui o
    // próprio worker (ver relatório: mapeamento people_needed = helperCount + 1,
    // consistente com accept_proposal's slots_needed = people_needed - 1).
    final peopleNeeded = draft.needsHelpers ? draft.helperCount + 1 : 1;
    final inDays = draft.durationUnit == view.WorkerProposalDurationUnit.days;
    final fixed = draft.pricingMode == ProposalPricingMode.fixedTotal;

    try {
      await ref.read(proposalRepositoryProvider).createProposal(
            jobId: widget.jobId,
            pricingMode: draft.pricingMode,
            hourlyRate: fixed ? null : draft.price,
            totalPrice: fixed ? draft.price : null,
            estimatedHoursMin:
                inDays ? null : draft.minimumDuration.toDouble(),
            estimatedHoursMax:
                inDays ? null : draft.maximumDuration?.toDouble(),
            estimatedDaysMin: inDays ? draft.minimumDuration : null,
            estimatedDaysMax: inDays ? draft.maximumDuration : null,
            includes: draft.includeIds.toList(),
            validUntil: DateUtils.dateOnly(DateTime.now())
                .add(Duration(days: draft.validityDays)),
            peopleNeeded: peopleNeeded,
            helpersEquipmentRequired: draft.helpersEquipmentRequired,
            notes: draft.message.trim().isEmpty ? null : draft.message.trim(),
            scheduledDate: draft.scheduledDate,
            scheduledTime: _timeSlotToScheduledTime[draft.timeSlotId],
            scheduledFlexible: false,
          );
      if (!mounted) return;
      // Regra T4: navegar → aviso → invalidar. Sem stack (link direto)
      // volta ao detalhe do pedido em vez de rebentar no pop.
      if (router.canPop()) {
        router.pop();
      } else {
        router.go('/worker/job/${widget.jobId}');
      }
      toast.show('Proposta enviada!');
      invalidateWorkerLists(ref, jobId: widget.jobId);
    } catch (e) {
      if (!mounted) return;
      // O pedido fechou ou foi aceite outra proposta entretanto
      // (create_proposal: "Este pedido já não está disponível.").
      final closed = e.toString().contains('já não está disponível');
      setState(() {
        _jobClosed = closed;
        _submitError = closed ? null : friendlyError(e);
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_lastModeLoaded) {
      return const Scaffold(body: AppScreenLoadingSkeleton());
    }

    final workerProfile = ref.watch(workerProfileProvider).asData?.value;
    final defaultRate = workerProfile?.defaultHourlyRate;
    final includeOptions =
        ref.watch(proposalIncludeOptionsProvider).asData?.value ?? const [];
    // O formulário só lê a data inicial ao abrir: espera pelo pedido para
    // abrir já com a data do cliente. Se o pedido falhar, abre sem ela.
    final jobAsync = ref.watch(jobByIdProvider(widget.jobId));
    if (jobAsync.isLoading && !jobAsync.hasValue) {
      return const Scaffold(body: AppScreenLoadingSkeleton());
    }
    final job = jobAsync.asData?.value;
    final initialDate =
        job == null ? null : proposalInitialDate(job, DateTime.now());
    final serviceName = job == null
        ? null
        : ref
            .watch(serviceTypesProvider)
            .asData
            ?.value
            .where((s) => s.id == job.serviceTypeId)
            .map((s) => s.name)
            .firstOrNull;

    final suggestedLabel = (defaultRate != null && defaultRate > 0)
        ? hourlyRateLabel(defaultRate)
        : null;

    return view.WorkerSubmitProposalScreen(
      jobSubtitle: [
        ?serviceName,
        ?job?.sizeEstimate?.label.split(' (').first,
      ].join(' · '),
      clientDateLabel: job == null ? null : jobPreferredDateLabel(job),
      initialDate: initialDate == null ? null : _dateSelection(initialDate),
      initialPricingMode: _lastMode ?? ProposalPricingMode.hourly,
      pricingModeHint: _lastMode == ProposalPricingMode.fixedTotal
          ? 'Escolhemos o valor total porque o usaste da última vez.'
          : null,
      suggestedHourlyPriceLabel: suggestedLabel,
      timeSlots: _timeSlots,
      durationOptions: _durationOptions,
      dayDurationOptions: _dayDurationOptions,
      includeOptions: [
        for (final o in includeOptions)
          view.WorkerProposalIncludeViewData(id: o.slug, label: o.label),
      ],
      initialValidity: _validity(_defaultValidityDays),
      onBack: () => goBackOrToRoleHome(context),
      onSelectDate: _selectDate,
      onSelectValidity: _selectValidity,
      onSubmit: _submit,
      initialHourlyPrice:
          (defaultRate != null && defaultRate > 0) ? defaultRate : null,
      isSubmitting: _submitting,
      submitError: _submitError,
      jobClosed: _jobClosed,
    );
  }
}
