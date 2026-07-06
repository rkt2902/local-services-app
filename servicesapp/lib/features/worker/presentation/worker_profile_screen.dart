import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/geocoding_service.dart';
import '../../../core/utils/error_utils.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_providers.dart';
import '../../ratings/presentation/ratings_sheet.dart';
import '../application/worker_providers.dart';
import '../data/worker_profile_model.dart';

class WorkerProfileScreen extends ConsumerStatefulWidget {
  const WorkerProfileScreen({super.key});

  @override
  ConsumerState<WorkerProfileScreen> createState() =>
      _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends ConsumerState<WorkerProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  final _toolController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  int _radiusKm = 10;
  double? _baseLat;
  double? _baseLng;
  bool _loadingLocation = false;
  String? _locationError;
  File? _newAvatar;
  final List<String> _tools = [];
  final List<String> _selectedServiceTypeIds = [];
  bool _saving = false;
  String _locationName = '';
  bool _initialized = false;
  bool _geocoding = false;
  bool _showManualCoords = false;
  final _addressSearchController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _hourlyRateController.dispose();
    _toolController.dispose();
    _addressSearchController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  void _initFields(WorkerProfile profile) {
    if (_initialized) return;
    _nameController.text = profile.fullName;
    _phoneController.text = profile.phone;
    _bioController.text = profile.bio ?? '';
    _hourlyRateController.text =
        (profile.defaultHourlyRate != null && profile.defaultHourlyRate! > 0)
            ? profile.defaultHourlyRate!.toStringAsFixed(2)
            : '';
    _radiusKm = profile.radiusKm;
    _baseLat = profile.baseLat;
    _baseLng = profile.baseLng;
    _locationName = profile.locationName;
    _tools
      ..clear()
      ..addAll(profile.tools);
    _selectedServiceTypeIds
      ..clear()
      ..addAll(profile.serviceTypeIds);
    _initialized = true;
  }

  Future<void> _geocodeAddress() async {
    final text = _addressSearchController.text.trim();
    if (text.isEmpty) return;
    setState(() => _geocoding = true);
    try {
      final locations = await locationFromAddress(text);
      if (!mounted) return;
      if (locations.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Morada não encontrada.'),
        ));
        return;
      }
      final lat = locations.first.latitude;
      final lng = locations.first.longitude;
      setState(() {
        _baseLat = lat;
        _baseLng = lng;
      });
      GeocodingService.reverseGeocode(lat, lng).then((result) {
        if (!mounted || result == null) return;
        setState(() => _locationName = result.locationName);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Erro ao pesquisar morada.'),
      ));
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  void _applyManualCoords() {
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());
    if (lat != null && lng != null) {
      setState(() {
        _baseLat = lat;
        _baseLng = lng;
      });
    }
  }

  Future<void> _getLocation() async {
    setState(() {
      _loadingLocation = true;
      _locationError = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Serviço de localização desativado.');
      }
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
      setState(() {
        _baseLat = position.latitude;
        _baseLng = position.longitude;
      });
      GeocodingService.reverseGeocode(position.latitude, position.longitude)
          .then((result) {
        if (!mounted || result == null) return;
        setState(() => _locationName = result.locationName);
      });
    } catch (e) {
      if (!mounted) return;
      setState(
          () => _locationError = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  Future<void> _pickAvatar() async {
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
    final picked = await ImagePicker()
        .pickImage(source: source, imageQuality: 70, maxWidth: 400);
    if (!mounted) return;
    if (picked != null) setState(() => _newAvatar = File(picked.path));
  }

  void _addTool() {
    final tool = _toolController.text.trim();
    if (tool.isEmpty) return;
    setState(() {
      _tools.add(tool);
      _toolController.clear();
    });
  }

  Future<void> _save(WorkerProfile current) async {
    if (!_formKey.currentState!.validate()) return;
    if (_baseLat == null || _baseLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Localização em falta.'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      final user = ref.read(currentUserProvider)!;
      final repo = ref.read(workerRepositoryProvider);
      String? avatarUrl = current.avatarUrl;
      if (_newAvatar != null) {
        avatarUrl = await repo.uploadAvatar(user.id, _newAvatar!);
      }
      await repo.updateProfile(current.copyWith(
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        avatarUrl: avatarUrl,
        bio: _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
        defaultHourlyRate:
            double.tryParse(_hourlyRateController.text.trim()),
        radiusKm: _radiusKm,
        baseLat: _baseLat,
        baseLng: _baseLng,
        locationName: _locationName,
        tools: List.from(_tools),
        serviceTypeIds: List.from(_selectedServiceTypeIds),
      ));
      ref.invalidate(workerProfileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil atualizado.')),
      );
    } catch (e) {
      debugPrint('[BUG1_DIAG] ${e.runtimeType}: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(workerProfileProvider);
    final serviceTypesAsync = ref.watch(serviceTypesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('O meu perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () async {
              final router = GoRouter.of(context);
              await ref.read(authControllerProvider.notifier).signOut();
              if (!mounted) return;
              router.go('/');
            },
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('Perfil não encontrado.'));
          }
          _initFields(profile);
          final avatarProvider = _newAvatar != null
              ? FileImage(_newAvatar!) as ImageProvider
              : (profile.avatarUrl != null
                  ? NetworkImage(profile.avatarUrl!)
                  : null);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _pickAvatar,
                      child: CircleAvatar(
                        radius: 48,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        backgroundImage: avatarProvider,
                        child: avatarProvider == null
                            ? Icon(Icons.person,
                                size: 48, color: theme.colorScheme.primary)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: _pickAvatar,
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Alterar foto'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome completo',
                      prefixIcon: Icon(Icons.person_outlined),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Introduz o teu nome.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Telefone',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Introduz o teu telefone.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _bioController,
                    decoration: const InputDecoration(
                      labelText: 'Apresentação (opcional)',
                      prefixIcon: Icon(Icons.info_outline),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  Text('Localização base', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_baseLat != null && _baseLng != null)
                    Chip(
                      avatar: Icon(Icons.check_circle,
                          color: theme.colorScheme.primary),
                      label: Text(
                          '${_baseLat!.toStringAsFixed(4)}, ${_baseLng!.toStringAsFixed(4)}'),
                    ),
                  if (_locationError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_locationError!,
                          style:
                              TextStyle(color: theme.colorScheme.error)),
                    ),
                  OutlinedButton.icon(
                    onPressed: _loadingLocation ? null : _getLocation,
                    icon: _loadingLocation
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location),
                    label: const Text('Atualizar localização'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressSearchController,
                    decoration: InputDecoration(
                      labelText: 'Pesquisar morada',
                      prefixIcon: const Icon(Icons.place_outlined),
                      suffixIcon: _geocoding
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: _geocodeAddress,
                            ),
                    ),
                    onFieldSubmitted: (_) => _geocodeAddress(),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () =>
                        setState(() => _showManualCoords = !_showManualCoords),
                    child: Text(_showManualCoords
                        ? 'Ocultar coordenadas'
                        : 'Introduzir coordenadas manualmente'),
                  ),
                  if (_showManualCoords) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _latController,
                            decoration: const InputDecoration(
                                labelText: 'Latitude'),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true, signed: true),
                            onChanged: (_) => _applyManualCoords(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _lngController,
                            decoration: const InputDecoration(
                                labelText: 'Longitude'),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true, signed: true),
                            onChanged: (_) => _applyManualCoords(),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text('Raio de atuação: $_radiusKm km',
                      style: theme.textTheme.titleMedium),
                  Slider(
                    value: _radiusKm.toDouble(),
                    min: 1,
                    max: 50,
                    divisions: 49,
                    label: '$_radiusKm km',
                    onChanged: (v) => setState(() => _radiusKm = v.round()),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _hourlyRateController,
                    decoration: const InputDecoration(
                      labelText: 'Preço/hora (€) — opcional',
                      prefixIcon: Icon(Icons.euro_outlined),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 24),
                  Text('Serviços que faço',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  serviceTypesAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) =>
                        Text('Erro ao carregar serviços: ${friendlyError(e)}'),
                    data: (types) => Wrap(
                      spacing: 8,
                      children: types.map((t) {
                        final selected =
                            _selectedServiceTypeIds.contains(t.id);
                        return FilterChip(
                          label: Text(t.name),
                          selected: selected,
                          onSelected: (v) => setState(() {
                            if (v) {
                              _selectedServiceTypeIds.add(t.id);
                            } else {
                              _selectedServiceTypeIds.remove(t.id);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Ferramentas', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _toolController,
                          decoration: const InputDecoration(
                            labelText: 'Adicionar ferramenta',
                            prefixIcon: Icon(Icons.build_outlined),
                          ),
                          onFieldSubmitted: (_) => _addTool(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                          onPressed: _addTool,
                          icon: const Icon(Icons.add)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _tools
                        .map((t) => Chip(
                              label: Text(t),
                              onDeleted: () =>
                                  setState(() => _tools.remove(t)),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: () {
                      final userId = ref
                          .read(supabaseClientProvider)
                          .auth
                          .currentUser
                          ?.id;
                      if (userId == null) return;
                      showRatingsSheet(
                        context,
                        workerId: userId,
                        workerName: 'As minhas avaliações',
                      );
                    },
                    icon: const Icon(Icons.star_outline_rounded),
                    label: const Text('Ver as minhas avaliações'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _saving ? null : () => _save(profile),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Guardar alterações'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
