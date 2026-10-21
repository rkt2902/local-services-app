import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/router/app_back_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_bar_title.dart';
import '../../../core/widgets/app_date_picker.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/bottom_actions_bar.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../client/application/job_request_form.dart';
import '../../client/presentation/widgets/job_location_picker.dart';
import '../../client/presentation/widgets/job_schedule_fields.dart';
import '../application/job_providers.dart';
import '../data/job_model.dart';

/// Mensagem quando a base de dados ainda não tem `update_job_request`
/// (migration 0049 por aplicar).
const _editUnavailableMessage =
    'Ainda não é possível editar pedidos. Tenta mais tarde.';

/// "Editar pedido" (cliente), só enquanto o pedido está `open`.
///
/// Muda descrição, data (fixa, flexível ou disponibilidade em texto livre)
/// e morada/pin. As fotos ficam como estão. Grava pela RPC
/// `update_job_request` (migration 0049); os jardineiros com proposta
/// pendente são avisados pelo servidor. Sub-fluxo fora do `ClientShell`,
/// alcançado pelo botão "Editar pedido" no detalhe do pedido.
class ClientEditJobScreen extends ConsumerWidget {
  const ClientEditJobScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(jobByIdProvider(jobId)).when(
          loading: () => const Scaffold(body: AppScreenLoadingSkeleton()),
          error: (e, _) => _EditJobMessage(
            message: friendlyError(e),
            onRetry: () => ref.invalidate(jobByIdProvider(jobId)),
          ),
          data: (job) {
            if (job == null) {
              return const _EditJobMessage(message: 'Pedido não encontrado.');
            }
            if (job.status != JobStatus.open) {
              return const _EditJobMessage(
                message: 'Este pedido já não pode ser editado: só se editam '
                    'pedidos à espera de propostas.',
              );
            }
            final serviceName = ref
                    .watch(serviceTypesProvider)
                    .asData
                    ?.value
                    .where((s) => s.id == job.serviceTypeId)
                    .map((s) => s.name)
                    .firstOrNull ??
                '';
            return _EditJobForm(job: job, serviceName: serviceName);
          },
        );
  }
}

/// Opções de data em "Editar pedido" (sem a urgência do wizard, que a RPC
/// não muda).
enum _DateChoice { fixed, flexible, availability }

class _EditJobForm extends ConsumerStatefulWidget {
  const _EditJobForm({required this.job, required this.serviceName});

  final JobRequest job;
  final String serviceName;

  @override
  ConsumerState<_EditJobForm> createState() => _EditJobFormState();
}

class _EditJobFormState extends ConsumerState<_EditJobForm> {
  final _descriptionController = TextEditingController();
  final _availabilityController = TextEditingController();

  late _DateChoice _dateChoice;
  DateTime? _date;
  late JobLocationValue _location;
  late final JobLocationValue _initialLocation;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final job = widget.job;
    _descriptionController.text = job.description;
    _availabilityController.text = job.availabilityText ?? '';
    _dateChoice = switch (job.dateMode) {
      DateMode.fixed => _DateChoice.fixed,
      DateMode.flexible => _DateChoice.flexible,
      DateMode.availability => _DateChoice.availability,
    };
    // Uma data que já passou não se mantém: obriga a escolher outra.
    final date = job.preferredDate;
    _date = date != null && !isPastDay(date, DateTime.now()) ? date : null;
    final hasPin = job.locationLat != 0 || job.locationLng != 0;
    _initialLocation = JobLocationValue(
      addressText: job.addressText,
      addressAutoFilled: false,
      locationArea: job.locationArea,
      lat: hasPin ? job.locationLat : null,
      lng: hasPin ? job.locationLng : null,
    );
    _location = _initialLocation;
    _descriptionController.addListener(_rebuild);
    _availabilityController.addListener(_rebuild);
  }

  @override
  void dispose() {
    _descriptionController.removeListener(_rebuild);
    _availabilityController.removeListener(_rebuild);
    _descriptionController.dispose();
    _availabilityController.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  DateMode get _dateMode => switch (_dateChoice) {
        _DateChoice.fixed => DateMode.fixed,
        _DateChoice.flexible => DateMode.flexible,
        _DateChoice.availability => DateMode.availability,
      };

  bool get _canSave {
    if (_saving) return false;
    final description = _descriptionController.text.trim();
    if (description.length < jobDescriptionMinLength ||
        description.length > jobDescriptionMaxLength) {
      return false;
    }
    if (_dateChoice == _DateChoice.fixed && _date == null) return false;
    if (_dateChoice == _DateChoice.availability &&
        availabilityTextError(_availabilityController.text) != null) {
      return false;
    }
    return _location.hasPin;
  }

  Future<void> _pickDate() async {
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final job = widget.job;
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final dateMode = _dateMode;
    try {
      await ref.read(jobRepositoryProvider).updateJobRequest(
            jobId: job.id,
            description: _descriptionController.text.trim(),
            dateMode: dateMode,
            preferredDate: dateMode == DateMode.fixed ? _date : null,
            availabilityText: dateMode == DateMode.availability
                ? _availabilityController.text.trim()
                : null,
            addressText: _location.addressText,
            locationLat: _location.lat!,
            locationLng: _location.lng!,
            locationArea: _location.locationArea,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
        content: Text(
          rpcErrorMessage(e, unavailableMessage: _editUnavailableMessage),
        ),
        backgroundColor: AppStatusColor.cancelled.foreground,
      ));
      return;
    }
    if (!mounted) return;

    // T4: navegar → SnackBar → invalidar.
    goBackOr(context, '/client/job/${job.id}');
    messenger.showSnackBar(SnackBar(
      content: Text(job.proposalCount > 0
          ? 'Pedido atualizado. Avisámos os jardineiros que já propuseram.'
          : 'Pedido atualizado.'),
    ));
    container.invalidate(jobByIdProvider(job.id));
    container.invalidate(clientJobsProvider);
  }

  Widget _dateOption(int index, _DateChoice value, String title,
      String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: AppStaggeredEntrance(
        index: index,
        child: JobOptionCard(
          title: title,
          subtitle: subtitle,
          selected: _dateChoice == value,
          onPressed: () => setState(() => _dateChoice = value),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final job = widget.job;
    final descriptionLength = _descriptionController.text.length;
    final sectionLabelStyle =
        textTheme.labelMedium?.copyWith(color: AppColors.textPrimary);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: const AppBackButton(),
        titleSpacing: 0,
        title: AppBarTitle(
          title: 'Editar pedido',
          subtitle: widget.serviceName.isEmpty ? null : widget.serviceName,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (job.proposalCount > 0) ...[
                      AppStaggeredEntrance(
                        index: 0,
                        child: _ProposalsWarning(
                          proposalCount: job.proposalCount,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    AppStaggeredEntrance(
                      index: 1,
                      child: Text('Descrição', style: sectionLabelStyle),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: 1,
                      child: AppTextField(
                        controller: _descriptionController,
                        label: 'Descrição',
                        minLines: 4,
                        maxLines: 7,
                        textInputAction: TextInputAction.newline,
                        maxLength: jobDescriptionMaxLength,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '$descriptionLength/$jobDescriptionMaxLength',
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (_descriptionController.text.trim().length <
                        jobDescriptionMinLength)
                      Text(
                        'A descrição deve ter pelo menos '
                        '$jobDescriptionMinLength caracteres.',
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 2,
                      child: Text('Quando', style: sectionLabelStyle),
                    ),
                    _dateOption(2, _DateChoice.fixed, 'Data fixa',
                        'Escolhe o dia que te dá jeito'),
                    _dateOption(3, _DateChoice.flexible, 'Flexível',
                        'Combinas a data com o jardineiro'),
                    _dateOption(
                      4,
                      _DateChoice.availability,
                      'Indicar disponibilidade',
                      'Diz por palavras tuas quando dá jeito',
                    ),
                    if (_dateChoice == _DateChoice.fixed) ...[
                      const SizedBox(height: AppSpacing.sm),
                      JobDateField(
                        key: const ValueKey('edit_job_date'),
                        date: _date,
                        onPressed: _pickDate,
                      ),
                      if (_date == null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'Escolhe uma data a partir de hoje.',
                          style: textTheme.labelMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                    if (_dateChoice == _DateChoice.availability) ...[
                      const SizedBox(height: AppSpacing.sm),
                      AvailabilityTextField(
                        key: const ValueKey('edit_job_availability'),
                        controller: _availabilityController,
                        maxLength: availabilityTextMaxLength,
                        hintText: availabilityTextHint,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    JobLocationPicker(
                      key: const ValueKey('edit_job_location'),
                      initial: _initialLocation,
                      staggerStartIndex: 5,
                      onChanged: (value) => setState(() => _location = value),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'As fotos do pedido ficam como estão.',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            BottomActionsBar(children: [
              PrimaryActionButton(
                label: _saving ? 'A guardar...' : 'Guardar alterações',
                isLoading: _saving,
                onPressed: _canSave ? _save : null,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _ProposalsWarning extends StatelessWidget {
  const _ProposalsWarning({required this.proposalCount});

  final int proposalCount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = AppStatusColor.waiting;
    final who = proposalCount == 1
        ? 'O jardineiro que já propôs vai ser avisado'
        : 'Os $proposalCount jardineiros que já propuseram vão ser avisados';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: color.foreground),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '$who das alterações. As propostas mantêm-se.',
              style: textTheme.bodyMedium?.copyWith(color: color.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ecrã só com uma mensagem (erro, pedido inexistente ou já não editável),
/// sempre com voltar.
class _EditJobMessage extends StatelessWidget {
  const _EditJobMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: const AppBackButton(),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: AppStaggeredEntrance(
              index: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium
                        ?.copyWith(color: AppColors.textPrimary),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton(
                      onPressed: onRetry,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
