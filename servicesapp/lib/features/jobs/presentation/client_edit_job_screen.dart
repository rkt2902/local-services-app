import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/router/app_back_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_bar_title.dart';
import '../../../core/widgets/app_date_picker.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../../core/widgets/bottom_actions_bar.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../client/application/job_request_form.dart';
import '../../client/presentation/widgets/job_location_picker.dart';
import '../../client/presentation/widgets/job_schedule_fields.dart';
import '../application/job_providers.dart';
import '../data/job_model.dart';
import '../../../core/widgets/app_toast.dart';

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
              return _EditJobLocked(job: job);
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

  late DateMode _dateMode;
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
    _dateMode = job.dateMode;
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

  bool get _canSave {
    if (_saving) return false;
    final description = _descriptionController.text.trim();
    if (description.length < jobDescriptionMinLength ||
        description.length > jobDescriptionMaxLength) {
      return false;
    }
    if (_dateMode == DateMode.fixed && _date == null) return false;
    if (_dateMode == DateMode.availability &&
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
    final toast = AppToast.of(context);
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
      toast.error(rpcErrorMessage(e, unavailableMessage: _editUnavailableMessage));
      return;
    }
    if (!mounted) return;

    // T4: navegar → SnackBar → invalidar.
    goBackOr(context, '/client/job/${job.id}');
    final notified = switch (job.proposalCount) {
      0 => '',
      1 => ' Avisámos 1 jardineiro.',
      final n => ' Avisámos $n jardineiros.',
    };
    toast.show('Pedido atualizado.$notified');
    container.invalidate(jobByIdProvider(job.id));
    container.invalidate(clientJobsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final job = widget.job;
    final description = _descriptionController.text;
    final descriptionTooShort =
        description.trim().length < jobDescriptionMinLength;
    final sectionTitleStyle =
        textTheme.titleMedium?.copyWith(color: AppColors.textPrimary);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Fechar',
          onPressed:
              _saving ? null : () => goBackOr(context, '/client/job/${job.id}'),
          icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
        ),
        titleSpacing: 0,
        title: AppBarTitle(
          title: 'Editar pedido',
          subtitle: widget.serviceName.isEmpty ? null : widget.serviceName,
        ),
      ),
      body: PopScope(
        canPop: !_saving,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (job.proposalCount > 0) ...[
                        AppStaggeredEntrance(
                          index: 0,
                          child: _ProposalsNotice(
                            proposalCount: job.proposalCount,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      AppStaggeredEntrance(
                        index: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Descrição', style: sectionTitleStyle),
                            const SizedBox(height: AppSpacing.sm),
                            _DescriptionField(
                              controller: _descriptionController,
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              '${description.length} / '
                              '$jobDescriptionMinLength mín.',
                              textAlign: TextAlign.right,
                              style: textTheme.labelMedium?.copyWith(
                                color: descriptionTooShort
                                    ? AppStatusColor.cancelled.foreground
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppStaggeredEntrance(
                        index: 2,
                        child: JobScheduleFields(
                          title: 'Quando',
                          dateMode: _dateMode,
                          onDateModeChanged: (mode) =>
                              setState(() => _dateMode = mode),
                          date: _date,
                          onPickDate: _pickDate,
                          availabilityController: _availabilityController,
                          missingDateHint: 'Escolhe uma data a partir de hoje.',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      JobLocationPicker(
                        key: const ValueKey('edit_job_location'),
                        initial: _initialLocation,
                        staggerStartIndex: 3,
                        onChanged: (value) => setState(() => _location = value),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppStaggeredEntrance(
                        index: 6,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.photo_library_outlined,
                              size: AppSizes.inlineIcon,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                'As fotos do pedido ficam como estão.',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
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
      ),
    );
  }
}

/// Campo da descrição sem rótulo (o título da secção está por cima).
class _DescriptionField extends StatelessWidget {
  const _DescriptionField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: color),
        );
    return TextField(
      controller: controller,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      minLines: 3,
      maxLines: 7,
      maxLength: jobDescriptionMaxLength,
      style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
      decoration: InputDecoration(
        counterText: '',
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.all(AppSpacing.md),
        enabledBorder: border(AppColors.divider),
        focusedBorder: border(AppColors.primary),
        border: border(AppColors.divider),
      ),
    );
  }
}

/// Aviso azul de que os jardineiros que já propuseram vão ser avisados.
class _ProposalsNotice extends StatelessWidget {
  const _ProposalsNotice({required this.proposalCount});

  final int proposalCount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = AppStatusColor.info;
    final text = proposalCount == 1
        ? 'O jardineiro que já propôs vai ser avisado das alterações.'
        : 'Os $proposalCount jardineiros que já propuseram vão ser '
            'avisados das alterações.';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: color.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodyMedium?.copyWith(color: color.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Este pedido já não pode ser editado" (pedido que já saiu de `open`),
/// com "Ver pedido" para voltar ao detalhe.
class _EditJobLocked extends StatelessWidget {
  const _EditJobLocked({required this.job});

  final JobRequest job;

  @override
  Widget build(BuildContext context) {
    final message = job.status == JobStatus.confirmed
        ? 'Já escolheste um jardineiro. Para mudar a data, usa Remarcar.'
        : 'Só se editam pedidos à espera de propostas.';
    return _EditJobScaffold(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: AppEmptyState(
          icon: Icons.edit_off_outlined,
          tone: AppStatusColor.neutral,
          title: 'Este pedido já não pode ser editado',
          message: message,
          action: OutlinedButton(
            onPressed: () => goBackOr(context, '/client/job/${job.id}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.divider),
              minimumSize: const Size(
                AppSizes.emptyActionMinWidth,
                AppSizes.compactButtonHeight,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
            ),
            child: const Text('Ver pedido'),
          ),
        ),
      ),
    );
  }
}

/// Ecrã só com uma mensagem (erro ou pedido inexistente), sempre com
/// fechar.
class _EditJobMessage extends StatelessWidget {
  const _EditJobMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _EditJobScaffold(
      child: AppStaggeredEntrance(
        index: 0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style:
                  textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
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
    );
  }
}

/// Moldura dos estados sem formulário: fechar no topo e conteúdo ao centro.
class _EditJobScaffold extends StatelessWidget {
  const _EditJobScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Fechar',
          onPressed: () => goBackOr(context, '/client/jobs'),
          icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: child,
          ),
        ),
      ),
    );
  }
}
