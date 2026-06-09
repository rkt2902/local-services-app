import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/enums.dart';
import '../../auth/application/auth_providers.dart';
import '../application/job_providers.dart';

class CreateJobScreen extends ConsumerStatefulWidget {
  const CreateJobScreen({super.key});

  @override
  ConsumerState<CreateJobScreen> createState() => _CreateJobScreenState();
}

class _CreateJobScreenState extends ConsumerState<CreateJobScreen> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _mapController = MapController();

  String? _selectedServiceTypeId;
  LatLng? _pinPosition;
  bool _loadingLocation = false;
  String? _locationError;
  bool _isFlexible = false;
  DateTime? _selectedDate;
  Urgency _urgency = Urgency.normal;
  SizeEstimate? _sizeEstimate;
  final List<File> _photos = [];
  bool _saving = false;

  @override
  void dispose() {
    _addressController.dispose();
    _descriptionController.dispose();
    super.dispose();
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
      initialDate:
          _selectedDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickPhoto() async {
    if (_photos.length >= 2) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Câmara'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeria'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source);
    if (!mounted) return;
    if (picked != null) setState(() => _photos.add(File(picked.path)));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_pinPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Define a localização no mapa.'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    if (!_isFlexible && _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Escolhe uma data ou marca "Sem data definida".'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      final user = ref.read(currentUserProvider)!;
      final repo = ref.read(jobRepositoryProvider);

      final jobId = await repo.createJob(
        clientId: user.id,
        serviceTypeId: _selectedServiceTypeId!,
        addressText: _addressController.text.trim(),
        locationLat: _pinPosition!.latitude,
        locationLng: _pinPosition!.longitude,
        preferredDate: _isFlexible ? null : _selectedDate,
        urgency: _urgency,
        sizeEstimate: _sizeEstimate,
        description: _descriptionController.text.trim(),
      );

      for (final photo in _photos) {
        await repo.uploadJobPhoto(jobId: jobId, file: photo);
      }

      ref.invalidate(clientJobsProvider);

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.go('/client/home');
      messenger.showSnackBar(
        const SnackBar(content: Text('Pedido publicado com sucesso!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildPhotoSlot(int index) {
    final theme = Theme.of(context);
    if (index < _photos.length) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              _photos[index],
              width: 100,
              height: 100,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () => setState(() => _photos.removeAt(index)),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(2),
                child:
                    const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      );
    }
    return GestureDetector(
      onTap: _photos.length < 2 ? _pickPhoto : null,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surfaceContainerLow,
        ),
        child: Icon(
          Icons.add_a_photo_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serviceTypesAsync = ref.watch(serviceTypesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Novo pedido')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Service type ──────────────────────────────────────────────
              serviceTypesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Erro ao carregar serviços: $e'),
                data: (types) => DropdownButtonFormField<String>(
                  initialValue: _selectedServiceTypeId,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de serviço',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: types
                      .map((t) => DropdownMenuItem<String>(
                            value: t.id,
                            child: Text(t.name),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedServiceTypeId = v),
                  validator: (v) =>
                      v == null ? 'Seleciona o tipo de serviço.' : null,
                ),
              ),
              const SizedBox(height: 24),

              // ── Location ──────────────────────────────────────────────────
              Text('Localização', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 220,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter:
                          _pinPosition ?? const LatLng(38.7169, -9.1399),
                      initialZoom: 14,
                      onTap: (_, point) =>
                          setState(() => _pinPosition = point),
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
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.red,
                                size: 36,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_locationError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _locationError!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              OutlinedButton.icon(
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Morada / referência para o jardineiro',
                  helperText: 'Ex: Rua das Flores 23, portão azul',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
              const SizedBox(height: 24),

              // ── Preferred date ────────────────────────────────────────────
              Text('Data', style: theme.textTheme.titleMedium),
              SwitchListTile(
                value: _isFlexible,
                onChanged: (v) => setState(() {
                  _isFlexible = v;
                  if (v) _selectedDate = null;
                }),
                title: const Text('Sem data definida (o quanto antes)'),
                contentPadding: EdgeInsets.zero,
              ),
              if (!_isFlexible)
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    _selectedDate == null
                        ? 'Escolher data'
                        : '${_selectedDate!.day.toString().padLeft(2, '0')}/'
                            '${_selectedDate!.month.toString().padLeft(2, '0')}/'
                            '${_selectedDate!.year}',
                  ),
                ),
              const SizedBox(height: 24),

              // ── Urgency ───────────────────────────────────────────────────
              Text('Urgência', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<Urgency>(
                segments: const [
                  ButtonSegment(
                      value: Urgency.normal, label: Text('Normal')),
                  ButtonSegment(
                      value: Urgency.urgent, label: Text('Urgente')),
                ],
                selected: {_urgency},
                onSelectionChanged: (s) =>
                    setState(() => _urgency = s.first),
              ),
              const SizedBox(height: 24),

              // ── Size estimate ─────────────────────────────────────────────
              Text('Dimensão do trabalho',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Pequeno'),
                    selected: _sizeEstimate == SizeEstimate.small,
                    onSelected: (v) => setState(() =>
                        _sizeEstimate = v ? SizeEstimate.small : null),
                  ),
                  FilterChip(
                    label: const Text('Médio'),
                    selected: _sizeEstimate == SizeEstimate.medium,
                    onSelected: (v) => setState(() =>
                        _sizeEstimate = v ? SizeEstimate.medium : null),
                  ),
                  FilterChip(
                    label: const Text('Grande'),
                    selected: _sizeEstimate == SizeEstimate.large,
                    onSelected: (v) => setState(() =>
                        _sizeEstimate = v ? SizeEstimate.large : null),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Description ───────────────────────────────────────────────
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  prefixIcon: Icon(Icons.description_outlined),
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'A descrição é obrigatória.';
                  }
                  if (v.trim().length < 10) {
                    return 'A descrição deve ter pelo menos 10 caracteres.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // ── Photos ────────────────────────────────────────────────────
              Text('Fotos', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildPhotoSlot(0),
                  const SizedBox(width: 12),
                  _buildPhotoSlot(1),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Máx. 2 fotos. Ajudam o jardineiro a perceber o trabalho.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),

              // ── Submit ────────────────────────────────────────────────────
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Publicar pedido'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
