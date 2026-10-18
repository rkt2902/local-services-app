import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/router/app_back_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_date_picker.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_step_progress.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../application/client_create_job_wizard_provider.dart';
import '../application/job_request_form.dart';
import 'widgets/job_location_picker.dart';
import 'widgets/job_schedule_fields.dart';

/// Opção de dimensão apresentada no passo 2 — `id` corresponde ao
/// `SizeEstimate.value` real, para conversão direta sem tabela extra.
class ClientJobSizeOption {
  const ClientJobSizeOption({required this.id, required this.label});

  final String id;
  final String label;
}

// Quebra de linha explícita (`\n`) em vez do texto completo de
// `SizeEstimate.label` — o chip é estreito (3 por linha) e o valor
// completo ("Pequeno (até 100m²)") ficava a quebrar em pontos aleatórios;
// mesmas faixas de m², só formatadas para caber em 2 linhas curtas.
const _sizeOptions = [
  ClientJobSizeOption(id: 'small', label: 'Pequeno\n(até 100m²)'),
  ClientJobSizeOption(id: 'medium', label: 'Médio\n(100-300m²)'),
  ClientJobSizeOption(id: 'large', label: 'Grande\n(300m²+)'),
];

/// Escolha de prazo no passo 2.
///
/// NOTA DE INTEGRAÇÃO: não é o mesmo conceito que `Urgency` (o model real
/// só tem normal/urgent). "Flexível" aqui só define `DateMode.flexible` e
/// "Indicar disponibilidade" define `DateMode.availability` (texto livre
/// em `availability_text`); nenhum dos dois mexe em `Urgency`, que fica em
/// `Urgency.normal` por omissão.
enum ClientJobUrgency { flexible, normal, urgent, availability }

/// Passo 2/4 de "Criar pedido": prazo, dimensão e localização.
///
/// A localização (mapa/GPS/morada) vive no widget partilhado
/// `JobLocationPicker`, também usado em "Editar pedido".
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

  late ClientJobUrgency _urgency;
  DateTime? _selectedDate;
  String? _selectedSizeOptionId;
  late JobLocationValue _location;
  late final JobLocationValue _initialLocation;

  @override
  void initState() {
    super.initState();

    final wizard = ref.read(clientCreateJobWizardProvider);

    _urgency = switch (wizard.dateMode) {
      DateMode.availability => ClientJobUrgency.availability,
      DateMode.flexible => ClientJobUrgency.flexible,
      DateMode.fixed => wizard.urgency == Urgency.urgent
          ? ClientJobUrgency.urgent
          : ClientJobUrgency.normal,
    };
    _selectedDate = wizard.preferredDate;
    _selectedSizeOptionId = wizard.sizeEstimate?.value;
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

  bool get _requiresDate =>
      _urgency == ClientJobUrgency.normal || _urgency == ClientJobUrgency.urgent;

  bool get _requiresAvailability => _urgency == ClientJobUrgency.availability;

  bool get _canContinue {
    if (_selectedSizeOptionId == null) return false;
    if (!_location.hasPin) return false;
    if (_requiresDate && _selectedDate == null) return false;
    if (_requiresAvailability &&
        availabilityTextError(_availabilityController.text) != null) {
      return false;
    }
    return true;
  }

  void _continue() {
    if (!_canContinue) return;

    final urgency = _urgency == ClientJobUrgency.urgent
        ? Urgency.urgent
        : Urgency.normal;
    final dateMode = switch (_urgency) {
      ClientJobUrgency.flexible => DateMode.flexible,
      ClientJobUrgency.availability => DateMode.availability,
      ClientJobUrgency.normal || ClientJobUrgency.urgent => DateMode.fixed,
    };

    final notifier = ref.read(clientCreateJobWizardProvider.notifier);
    notifier.setSchedule(
      dateMode: dateMode,
      preferredDate: dateMode == DateMode.fixed ? _selectedDate : null,
      availabilityText: dateMode == DateMode.availability
          ? _availabilityController.text.trim()
          : '',
      urgency: urgency,
      sizeEstimate: SizeEstimate.fromValue(_selectedSizeOptionId!),
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

  Widget _urgencyOption(
    int index,
    ClientJobUrgency value,
    String title,
    String subtitle,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: AppStaggeredEntrance(
        index: index,
        child: JobOptionCard(
          title: title,
          subtitle: subtitle,
          selected: _urgency == value,
          onPressed: () => setState(() => _urgency = value),
        ),
      ),
    );
  }

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
        titleSpacing: 0,
        title: Text(
          'Criar pedido',
          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        ),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: AppStepProgress(currentStep: 2, totalSteps: 4),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppStaggeredEntrance(
                    index: 0,
                    child: Text(
                      'Prazo',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  _urgencyOption(1, ClientJobUrgency.flexible, 'Flexível',
                      'Posso agendar mais tarde'),
                  _urgencyOption(2, ClientJobUrgency.normal, 'Normal',
                      'Dentro de alguns dias'),
                  _urgencyOption(3, ClientJobUrgency.urgent, 'Urgente',
                      'O quanto antes'),
                  _urgencyOption(
                    4,
                    ClientJobUrgency.availability,
                    'Indicar disponibilidade',
                    'Diz por palavras tuas quando dá jeito',
                  ),
                  // Chaves nos itens destes blocos condicionais: sem elas,
                  // aparecer/desaparecer desloca os irmãos e o Flutter
                  // recria widgets com estado (ver JobLocationPicker).
                  if (_requiresDate) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      key: const ValueKey('schedule_date_label'),
                      index: 5,
                      child: Text(
                        'Quando precisas do serviço?',
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      key: const ValueKey('schedule_date_field'),
                      index: 5,
                      child: JobDateField(
                        date: _selectedDate,
                        onPressed: _pickDate,
                      ),
                    ),
                  ],
                  if (_requiresAvailability) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      key: const ValueKey('schedule_availability_field'),
                      index: 5,
                      child: AvailabilityTextField(
                        controller: _availabilityController,
                        maxLength: availabilityTextMaxLength,
                        hintText: availabilityTextHint,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  AppStaggeredEntrance(
                    index: 6,
                    child: Text(
                      'Dimensão aproximada',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppStaggeredEntrance(
                    index: 7,
                    child: _SizeSelector(
                      options: _sizeOptions,
                      selectedId: _selectedSizeOptionId,
                      onSelected: (id) {
                        setState(() => _selectedSizeOptionId = id);
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  JobLocationPicker(
                    key: const ValueKey('schedule_location'),
                    initial: _initialLocation,
                    staggerStartIndex: 8,
                    onChanged: (value) => setState(() => _location = value),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: PrimaryActionButton(
              label: 'Continuar',
              onPressed: _canContinue ? _continue : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _SizeSelector extends StatelessWidget {
  const _SizeSelector({
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  final List<ClientJobSizeOption> options;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          Expanded(
            child: _SizeChip(
              label: options[i].label,
              selected: selectedId == options[i].id,
              onPressed: () => onSelected(options[i].id),
            ),
          ),
          if (i < options.length - 1) const SizedBox(width: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _SizeChip extends StatelessWidget {
  const _SizeChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: selected ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: selected ? null : Border.all(color: AppColors.divider),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: textTheme.labelMedium?.copyWith(
              color: selected ? AppColors.surface : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
