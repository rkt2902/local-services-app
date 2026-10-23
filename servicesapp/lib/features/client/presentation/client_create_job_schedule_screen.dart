import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/router/app_back_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_date_picker.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_step_progress.dart';
import '../../../core/widgets/bottom_actions_bar.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../application/client_create_job_wizard_provider.dart';
import '../application/job_request_form.dart';
import 'widgets/job_location_picker.dart';
import 'widgets/job_schedule_fields.dart';
import 'widgets/direct_request_create_header.dart';

/// Texto curto de cada dimensão no chip do passo 2 (o chip é estreito:
/// 3 por linha). As faixas de m² são as mesmas de `SizeEstimate.label`.
String _sizeChipLabel(SizeEstimate size) => switch (size) {
      SizeEstimate.small => 'Até 100 m²',
      SizeEstimate.medium => '100-300 m²',
      SizeEstimate.large => '300+ m²',
    };

/// Por cima de "Continuar" enquanto falta alguma coisa no passo 2: o botão
/// cinzento sozinho não dizia o quê. `null` quando está tudo.
String? createJobScheduleMissingLabel({
  required bool hasDate,
  required bool hasLocation,
  required bool hasSize,
}) {
  final missing = [
    if (!hasDate) 'a data',
    if (!hasLocation) 'o local no mapa',
    if (!hasSize) 'a dimensão do espaço',
  ];
  if (missing.isEmpty) return null;
  final list = missing.length == 1
      ? missing.first
      : '${missing.sublist(0, missing.length - 1).join(', ')} e ${missing.last}';
  return 'Falta escolher $list.';
}

/// Passo 2/4 de "Criar pedido" (design U3, "Quando e onde"): modo da data,
/// localização, urgência e dimensão.
///
/// Os campos da data (`JobScheduleFields`) e a localização
/// (`JobLocationPicker`) são partilhados com "Editar pedido". A urgência é
/// independente do modo da data (`Urgency` só tem normal/urgente).
class ClientCreateJobScheduleScreen extends ConsumerStatefulWidget {
  const ClientCreateJobScheduleScreen({super.key, this.fromReview = false});

  /// `true` quando alcançado via "Editar" a partir da revisão (passo 4) —
  /// ver nota em `client_create_job_service_screen.dart`.
  final bool fromReview;

  @override
  ConsumerState<ClientCreateJobScheduleScreen> createState() {
    return _ClientCreateJobScheduleScreenState();
  }
}

class _ClientCreateJobScheduleScreenState
    extends ConsumerState<ClientCreateJobScheduleScreen> {
  final _availabilityController = TextEditingController();

  late DateMode _dateMode;
  late bool _urgent;
  DateTime? _selectedDate;
  SizeEstimate? _size;
  late JobLocationValue _location;
  late final JobLocationValue _initialLocation;

  @override
  void initState() {
    super.initState();

    final wizard = ref.read(clientCreateJobWizardProvider);

    _dateMode = wizard.dateMode;
    _urgent = wizard.urgency == Urgency.urgent;
    _selectedDate = wizard.preferredDate;
    _size = wizard.sizeEstimate;
    _availabilityController.text = wizard.availabilityText;
    _availabilityController.addListener(_onAvailabilityChanged);

    _initialLocation = JobLocationValue(
      addressText: wizard.addressText,
      addressAutoFilled: wizard.addressAutoFilled,
      locationArea: wizard.locationArea,
      lat: wizard.locationLat,
      lng: wizard.locationLng,
    );
    _location = _initialLocation;
  }

  @override
  void dispose() {
    _availabilityController.removeListener(_onAvailabilityChanged);
    _availabilityController.dispose();
    super.dispose();
  }

  void _onAvailabilityChanged() => setState(() {});

  Future<void> _pickDate() async {
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  bool get _hasDate {
    if (_dateMode == DateMode.fixed && _selectedDate == null) return false;
    if (_dateMode == DateMode.availability &&
        availabilityTextError(_availabilityController.text) != null) {
      return false;
    }
    return true;
  }

  bool get _canContinue => _size != null && _location.hasPin && _hasDate;

  void _continue() {
    if (!_canContinue) return;

    final notifier = ref.read(clientCreateJobWizardProvider.notifier);
    notifier.setSchedule(
      dateMode: _dateMode,
      preferredDate: _dateMode == DateMode.fixed ? _selectedDate : null,
      availabilityText: _dateMode == DateMode.availability
          ? _availabilityController.text.trim()
          : '',
      urgency: _urgent ? Urgency.urgent : Urgency.normal,
      sizeEstimate: _size!,
    );
    notifier.setLocation(
      addressText: _location.addressText,
      addressAutoFilled: _location.addressAutoFilled,
      locationArea: _location.locationArea,
      locationLat: _location.lat!,
      locationLng: _location.lng!,
    );

    if (widget.fromReview) {
      goBackOr(context, '/client/create-job/review');
    } else {
      context.push('/client/create-job/description');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final missingLabel = createJobScheduleMissingLabel(
      hasDate: _hasDate,
      hasLocation: _location.hasPin,
      hasSize: _size != null,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: const AppBackButton(),
        titleSpacing: 0,
        title: Text(
          'Quando e onde',
          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Center(
              child: Text(
                '2/4',
                style: textTheme.labelLarge
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: AppStepProgress(currentStep: 2, totalSteps: 4),
            ),
            const WizardCardRequestHeader(),
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
                    AppStaggeredEntrance(
                      index: 0,
                      child: JobScheduleFields(
                        dateMode: _dateMode,
                        onDateModeChanged: (mode) =>
                            setState(() => _dateMode = mode),
                        date: _selectedDate,
                        onPickDate: _pickDate,
                        availabilityController: _availabilityController,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    JobLocationPicker(
                      key: const ValueKey('schedule_location'),
                      initial: _initialLocation,
                      staggerStartIndex: 1,
                      onChanged: (value) => setState(() => _location = value),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 4,
                      child: Text(
                        'Dimensão do espaço *',
                        style: textTheme.titleMedium
                            ?.copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: 4,
                      child: Row(
                        children: [
                          for (final size in SizeEstimate.values) ...[
                            if (size != SizeEstimate.values.first)
                              const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: _AttributeChip(
                                label: _sizeChipLabel(size),
                                selected: _size == size,
                                selectedBackground: AppColors.primaryContainer,
                                selectedForeground: AppColors.primary,
                                onPressed: () => setState(() => _size = size),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 5,
                      child: Text(
                        'Urgência',
                        style: textTheme.titleMedium
                            ?.copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: 5,
                      child: Row(
                        children: [
                          Expanded(
                            child: _AttributeChip(
                              label: 'Normal',
                              selected: !_urgent,
                              selectedBackground: AppColors.divider,
                              selectedForeground: AppColors.textPrimary,
                              onPressed: () => setState(() => _urgent = false),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: _AttributeChip(
                              label: 'Urgente',
                              selected: _urgent,
                              selectedBackground:
                                  AppStatusColor.cancelled.background,
                              selectedForeground:
                                  AppStatusColor.cancelled.foreground,
                              onPressed: () => setState(() => _urgent = true),
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
              if (missingLabel != null) ...[
                Text(
                  missingLabel,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              PrimaryActionButton(
                label: 'Continuar',
                onPressed: _canContinue ? _continue : null,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Pílula de atributo (urgência ou dimensão), não um badge de estado.
class _AttributeChip extends StatelessWidget {
  const _AttributeChip({
    required this.label,
    required this.selected,
    required this.selectedBackground,
    required this.selectedForeground,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final Color selectedBackground;
  final Color selectedForeground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final foreground = selected ? selectedForeground : AppColors.textPrimary;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? selectedBackground : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSizes.attributeChipHeight,
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: selected ? selectedBackground : AppColors.divider,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
