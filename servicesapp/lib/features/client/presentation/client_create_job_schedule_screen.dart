import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/enums.dart';
import '../../../core/services/geocoding_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_step_progress.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../application/client_create_job_wizard_provider.dart';

/// Opção de dimensão apresentada no passo 2 — `id` corresponde ao
/// `SizeEstimate.value` real, para conversão direta sem tabela extra.
class ClientJobSizeOption {
  const ClientJobSizeOption({required this.id, required this.label});

  final String id;
  final String label;
}

const _sizeOptions = [
  ClientJobSizeOption(id: 'small', label: 'Pequeno'),
  ClientJobSizeOption(id: 'medium', label: 'Médio'),
  ClientJobSizeOption(id: 'large', label: 'Grande'),
];

/// Escolha de urgência no passo 2.
///
/// NOTA DE INTEGRAÇÃO: não é o mesmo conceito que `Urgency` (o model real
/// só tem normal/urgent). "Flexível" aqui só define `DateMode.flexible` —
/// não mexe em `Urgency`, que fica em `Urgency.normal` por omissão.
enum ClientJobUrgency { flexible, normal, urgent }

/// Passo 2/3 de "Criar pedido" — data, urgência, dimensão e localização.
///
/// A localização (mapa/GPS/morada) pertencia ao ecrã único original
/// (`create_job_screen.dart`) e não tem lugar no mockup de 3 passos — decidi
/// mantê-la aqui (fim deste passo) em vez de criar um 4º passo, para não
/// alargar o wizard além do que foi pedido ("fluxo de 3 passos"). Ver
/// relatório final para a razão desta escolha.
class ClientCreateJobScheduleScreen extends ConsumerStatefulWidget {
  const ClientCreateJobScheduleScreen({super.key});

  @override
  ConsumerState<ClientCreateJobScheduleScreen> createState() {
    return _ClientCreateJobScheduleScreenState();
  }
}

class _ClientCreateJobScheduleScreenState
    extends ConsumerState<ClientCreateJobScheduleScreen> {
  final _addressController = TextEditingController();
  final _mapController = MapController();

  late ClientJobUrgency _urgency;
  DateTime? _selectedDate;
  String? _selectedSizeOptionId;

  LatLng? _pinPosition;
  bool _loadingLocation = false;
  bool _geocoding = false;
  String? _locationError;

  @override
  void initState() {
    super.initState();

    final wizard = ref.read(clientCreateJobWizardProvider);

    _urgency = wizard.urgency == Urgency.urgent
        ? ClientJobUrgency.urgent
        : wizard.dateMode == DateMode.flexible
            ? ClientJobUrgency.flexible
            : ClientJobUrgency.normal;
    _selectedDate = wizard.preferredDate;
    _selectedSizeOptionId = wizard.sizeEstimate?.value;

    _addressController.text = wizard.addressText;
    if (wizard.locationLat != null && wizard.locationLng != null) {
      _pinPosition = LatLng(wizard.locationLat!, wizard.locationLng!);
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _geocode() async {
    final text = _addressController.text.trim();
    if (text.isEmpty) return;
    setState(() => _geocoding = true);
    try {
      final locations = await locationFromAddress(text);
      if (!mounted) return;
      if (locations.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Morada não encontrada. Tenta ser mais específico.'),
        ));
        return;
      }
      final loc = locations.first;
      final latlng = LatLng(loc.latitude, loc.longitude);
      setState(() => _pinPosition = latlng);
      _mapController.move(latlng, 14);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Erro ao pesquisar morada.'),
      ));
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  void _onMapTap(TapPosition _, LatLng point) {
    setState(() => _pinPosition = point);
    _reverseGeocodePin(point.latitude, point.longitude);
  }

  Future<void> _reverseGeocodePin(double lat, double lng) async {
    final result = await GeocodingService.reverseGeocode(lat, lng);
    if (result != null && mounted && _addressController.text.isEmpty) {
      setState(() => _addressController.text = result.addressText);
    }
  }

  Future<void> _getLocation() async {
    setState(() {
      _loadingLocation = true;
      _locationError = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Serviço de localização desativado.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Permissão de localização negada.');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(
            'Permissão negada permanentemente. Ativa nas definições.');
      }
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final latlng = LatLng(position.latitude, position.longitude);
      setState(() => _pinPosition = latlng);
      _mapController.move(latlng, 14);
      _reverseGeocodePin(position.latitude, position.longitude);
    } catch (e) {
      if (!mounted) return;
      setState(
          () => _locationError = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  bool get _requiresDate => _urgency != ClientJobUrgency.flexible;

  bool get _canContinue {
    if (_selectedSizeOptionId == null) return false;
    if (_pinPosition == null) return false;
    if (_requiresDate && _selectedDate == null) return false;
    return true;
  }

  void _continue() {
    if (!_canContinue) return;

    final urgency = _urgency == ClientJobUrgency.urgent
        ? Urgency.urgent
        : Urgency.normal;
    final dateMode =
        _urgency == ClientJobUrgency.flexible ? DateMode.flexible : DateMode.fixed;

    final notifier = ref.read(clientCreateJobWizardProvider.notifier);
    notifier.setSchedule(
      dateMode: dateMode,
      preferredDate: dateMode == DateMode.fixed ? _selectedDate : null,
      urgency: urgency,
      sizeEstimate: SizeEstimate.fromValue(_selectedSizeOptionId!),
    );
    notifier.setLocation(
      addressText: _addressController.text.trim(),
      locationLat: _pinPosition!.latitude,
      locationLng: _pinPosition!.longitude,
    );

    context.push('/client/create-job/description');
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
        leading: IconButton(
          onPressed: () => context.pop(),
          tooltip: 'Voltar',
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
        ),
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
            child: AppStepProgress(currentStep: 2, totalSteps: 3),
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
                      'Urgência',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppStaggeredEntrance(
                    index: 1,
                    child: _UrgencyOptionCard(
                      title: 'Flexível',
                      subtitle: 'Posso agendar mais tarde',
                      selected: _urgency == ClientJobUrgency.flexible,
                      onPressed: () {
                        setState(() => _urgency = ClientJobUrgency.flexible);
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppStaggeredEntrance(
                    index: 2,
                    child: _UrgencyOptionCard(
                      title: 'Normal',
                      subtitle: 'Dentro de alguns dias',
                      selected: _urgency == ClientJobUrgency.normal,
                      onPressed: () {
                        setState(() => _urgency = ClientJobUrgency.normal);
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppStaggeredEntrance(
                    index: 3,
                    child: _UrgencyOptionCard(
                      title: 'Urgente',
                      subtitle: 'O quanto antes',
                      selected: _urgency == ClientJobUrgency.urgent,
                      onPressed: () {
                        setState(() => _urgency = ClientJobUrgency.urgent);
                      },
                    ),
                  ),
                  if (_requiresDate) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 4,
                      child: Text(
                        'Quando precisa do serviço?',
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: 5,
                      child: _DateField(
                        date: _selectedDate,
                        onPressed: _pickDate,
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
                  AppStaggeredEntrance(
                    index: 8,
                    child: Text(
                      'Localização',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppStaggeredEntrance(
                    index: 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      child: SizedBox(
                        height: 200,
                        child: FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter:
                                _pinPosition ?? const LatLng(38.7169, -9.1399),
                            initialZoom: 14,
                            onTap: _onMapTap,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.example.servicesapp',
                            ),
                            if (_pinPosition != null)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: _pinPosition!,
                                    child: Icon(
                                      Icons.location_on,
                                      color: AppStatusColor.cancelled.foreground,
                                      size: 36,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if (_locationError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Text(
                        _locationError!,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  AppStaggeredEntrance(
                    index: 10,
                    child: OutlinedButton.icon(
                      onPressed: _loadingLocation ? null : _getLocation,
                      icon: _loadingLocation
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                      label: const Text('Usar a minha localização'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppStaggeredEntrance(
                    index: 11,
                    child: AppTextField(
                      controller: _addressController,
                      label: 'Morada / referência',
                      hintText: 'Ex: Rua das Flores 23, portão azul',
                      suffixIcon: _geocoding
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: _geocode,
                            ),
                    ),
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

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onPressed});

  final DateTime? date;
  final VoidCallback onPressed;

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  date == null ? 'Escolher data' : _formatDate(date!),
                  style: textTheme.bodyMedium?.copyWith(
                    color: date == null
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.calendar_month_outlined,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UrgencyOptionCard extends StatelessWidget {
  const _UrgencyOptionCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: selected ? AppColors.primaryContainer : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.primary : AppColors.surface,
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.divider,
                  ),
                ),
                child: selected
                    ? Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surface,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
            style: textTheme.labelMedium?.copyWith(
              color: selected ? AppColors.surface : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
