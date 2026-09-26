import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/geocoding_service.dart';
import '../../../core/utils/error_utils.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_providers.dart';
import '../../ratings/application/rating_providers.dart';
import '../application/worker_providers.dart';
import '../data/service_type_model.dart';
import '../data/worker_profile_model.dart';
import 'widgets/worker_edit_profile_view.dart' as view;

/// Formulário de edição do perfil do worker — extraído do antigo
/// `WorkerProfileScreen` quando este passou a ser um ecrã de resumo
/// (`WorkerAccountScreen`). Acedido via "Definições" na conta do worker.
///
/// Wrapper que liga os providers reais ao componente apresentacional em
/// widgets/worker_edit_profile_view.dart — este ficheiro é o único que fala
/// com Supabase; o widget de apresentação não sabe que Riverpod existe.
///
/// O formulário está organizado em 3 secções navegadas dentro do próprio
/// ecrã (sem trocar de rota) — este wrapper é quem guarda em memória o
/// rascunho completo (nome/telefone/bio/preço/localização/raio/serviços/
/// ferramentas), não cada secção isoladamente. Isto garante que uma
/// alteração feita numa secção não se perde ao navegar para outra sem
/// gravar essa primeira — `WorkerRepository.updateProfile` reescreve sempre
/// o perfil completo (não aceita update parcial por coluna), por isso
/// qualquer botão "Guardar", de qualquer secção, envia sempre o estado
/// atual de todas as outras.
class WorkerEditProfileScreen extends ConsumerStatefulWidget {
  const WorkerEditProfileScreen({super.key});

  @override
  ConsumerState<WorkerEditProfileScreen> createState() =>
      _WorkerEditProfileScreenState();
}

class _WorkerEditProfileScreenState
    extends ConsumerState<WorkerEditProfileScreen> {
  view.WorkerProfileEditSection _section = view.WorkerProfileEditSection.overview;

  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  final _hourlyRateController = TextEditingController();

  final _addressSearchController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  final _toolController = TextEditingController();
  final _serviceSearchController = TextEditingController();

  bool _initialized = false;

  int _radiusKm = 10;
  double? _baseLat;
  double? _baseLng;
  String _locationName = '';
  bool _showManualCoords = false;
  bool _loadingLocation = false;
  bool _geocoding = false;
  String? _locationError;

  File? _newAvatar;
  final List<String> _tools = [];
  final List<String> _selectedServiceTypeIds = [];

  @override
  void initState() {
    super.initState();
    // Comportamento já existente: coordenadas manuais aplicam-se a cada
    // alteração, não só ao gravar (ver `_applyManualCoords`).
    _latController.addListener(_applyManualCoords);
    _lngController.addListener(_applyManualCoords);
  }

  @override
  void dispose() {
    _latController.removeListener(_applyManualCoords);
    _lngController.removeListener(_applyManualCoords);
    _fullNameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _hourlyRateController.dispose();
    _addressSearchController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _toolController.dispose();
    _serviceSearchController.dispose();
    super.dispose();
  }

  void _initFields(WorkerProfile profile) {
    if (_initialized) return;
    _fullNameController.text = profile.fullName;
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

  // ── Localização (idêntico ao comportamento já existente) ─────────────────

  Future<void> _geocodeAddress() async {
    final text = _addressSearchController.text.trim();
    if (text.isEmpty) return;
    setState(() => _geocoding = true);
    try {
      final locations = await locationFromAddress(text);
      if (!mounted) return;
      if (locations.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Morada não encontrada.')));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Erro ao pesquisar morada.')));
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
        throw Exception('Permissão negada permanentemente. Ativa nas definições.');
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
      setState(() => _locationError = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  void _toggleManualCoordinates(bool enabled) {
    setState(() => _showManualCoords = enabled);
  }

  void _changeRadius(int value) {
    setState(() => _radiusKm = value);
  }

  // ── Foto (idêntico ao comportamento já existente) ─────────────────────────

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
    final picked =
        await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 400);
    if (!mounted) return;
    if (picked != null) setState(() => _newAvatar = File(picked.path));
  }

  // ── Serviços/ferramentas (idêntico ao comportamento já existente) ─────────

  void _toggleService(String id) {
    setState(() {
      if (_selectedServiceTypeIds.contains(id)) {
        _selectedServiceTypeIds.remove(id);
      } else {
        _selectedServiceTypeIds.add(id);
      }
    });
  }

  void _addTool() {
    final tool = _toolController.text.trim();
    if (tool.isEmpty) return;
    setState(() {
      _tools.add(tool);
      _toolController.clear();
    });
  }

  void _removeTool(String tool) {
    setState(() => _tools.remove(tool));
  }

  // ── Navegação entre secções ────────────────────────────────────────────────

  void _openSection(view.WorkerProfileEditSection section) {
    setState(() => _section = section);
  }

  void _backToOverview() {
    setState(() => _section = view.WorkerProfileEditSection.overview);
  }

  void _openRatings() {
    context.push('/worker/ratings');
  }

  Future<void> _signOut() async {
    final router = GoRouter.of(context);
    await ref.read(authControllerProvider.notifier).signOut();
    if (!mounted) return;
    router.go('/');
  }

  // ── Guardar ────────────────────────────────────────────────────────────────

  /// Estado atual de TODOS os campos, de todas as secções — inclui os que
  /// não pertencem à secção que está a gravar, para nenhuma alteração feita
  /// noutro sítio se perder (ver doc comment da classe).
  WorkerProfile _currentDraft(WorkerProfile loaded) => loaded.copyWith(
        fullName: _fullNameController.text.trim(),
        phone: _phoneController.text.trim(),
        bio: _bioController.text.trim().isEmpty ? null : _bioController.text.trim(),
        defaultHourlyRate: double.tryParse(_hourlyRateController.text.trim()),
        baseLat: _baseLat,
        baseLng: _baseLng,
        locationName: _locationName,
        radiusKm: _radiusKm,
        tools: List.of(_tools),
        serviceTypeIds: List.of(_selectedServiceTypeIds),
      );

  Future<bool> _persist({bool uploadAvatarIfNeeded = false}) async {
    final profile = ref.read(workerProfileProvider).value;
    if (profile == null) return false;
    final scaffold = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(workerRepositoryProvider);
      var draft = _currentDraft(profile);
      if (uploadAvatarIfNeeded && _newAvatar != null) {
        final user = ref.read(currentUserProvider)!;
        final avatarUrl = await repo.uploadAvatar(user.id, _newAvatar!);
        draft = draft.copyWith(avatarUrl: avatarUrl);
      }
      await repo.updateProfile(draft);
      ref.invalidate(workerProfileProvider);
      return true;
    } catch (e) {
      if (mounted) {
        scaffold.showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
      return false;
    }
  }

  Future<bool> _saveOverview() => _persist(uploadAvatarIfNeeded: true);

  Future<bool> _saveBaseLocation() async {
    if (_baseLat == null || _baseLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Localização em falta.'),
        backgroundColor: Colors.red,
      ));
      return false;
    }
    return _persist();
  }

  Future<bool> _saveServicesAndTools() => _persist();

  String? _fullNameValidator(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Introduz o teu nome.' : null;

  String? _phoneValidator(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Introduz o teu telefone.' : null;

  // ── Resumos formatados ───────────────────────────────────────────────────

  String get _locationSummaryLabel {
    if (_baseLat == null || _baseLng == null) return 'Ainda não definida';
    if (_locationName.isNotEmpty) return _locationName;
    return '${_baseLat!.toStringAsFixed(4)}, ${_baseLng!.toStringAsFixed(4)}';
  }

  String get _coordinatesLabel => (_baseLat != null && _baseLng != null)
      ? '${_baseLat!.toStringAsFixed(4)}, ${_baseLng!.toStringAsFixed(4)}'
      : '';

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(workerProfileProvider);
    final serviceTypesAsync = ref.watch(serviceTypesProvider);
    final userId = ref.watch(currentUserProvider)?.id;
    final ratingSummary =
        userId == null ? null : ref.watch(ratingSummaryProvider(userId)).asData?.value;

    final AsyncValue<view.WorkerProfileEditViewData?> dataAsync = profileAsync.when(
      loading: () => const AsyncValue.loading(),
      error: AsyncValue.error,
      data: (profile) {
        if (profile == null) return const AsyncValue.data(null);
        if (serviceTypesAsync.isLoading) return const AsyncValue.loading();
        if (serviceTypesAsync.hasError) {
          return AsyncValue.error(
            serviceTypesAsync.error!,
            serviceTypesAsync.stackTrace ?? StackTrace.current,
          );
        }

        _initFields(profile);

        final serviceTypes = serviceTypesAsync.value ?? const <ServiceType>[];
        final ratingLabel =
            ratingSummary == null ? '—' : ratingSummary.avgRating.toStringAsFixed(1);
        final reviewsLabel = ratingSummary == null
            ? '0 avaliações'
            : '${ratingSummary.ratingCount} avaliações';

        return AsyncValue.data(view.WorkerProfileEditViewData(
          profileId: profile.profileId,
          avatarImage: _newAvatar != null
              ? FileImage(_newAvatar!) as ImageProvider
              : (profile.avatarUrl != null ? NetworkImage(profile.avatarUrl!) : null),
          locationSummaryLabel: _locationSummaryLabel,
          locationNeedsDefinition: _baseLat == null || _baseLng == null,
          radiusKm: _radiusKm,
          radiusSummaryLabel: '$_radiusKm km',
          servicesSummaryLabel: _selectedServiceTypeIds.isEmpty
              ? 'Nenhum selecionado'
              : '${_selectedServiceTypeIds.length} selecionados',
          toolsSummaryLabel:
              _tools.isEmpty ? 'Nenhuma ferramenta' : '${_tools.length} ferramentas',
          ratingsSummaryLabel: '$ratingLabel · $reviewsLabel',
          baseLocation: view.WorkerBaseLocationViewData(
            manualCoordinatesEnabled: _showManualCoords,
            isResolvingLocation: _loadingLocation || _geocoding,
            resolvedLocationLabel: (_baseLat != null && _baseLng != null)
                ? (_locationName.isNotEmpty ? _locationName : 'Localização definida')
                : null,
            resolvedCoordinatesLabel:
                _coordinatesLabel.isEmpty ? null : _coordinatesLabel,
            radiusKm: _radiusKm,
            errorMessage: _locationError,
          ),
          servicesAndTools: view.WorkerServicesToolsViewData(
            selectedServicesCountLabel: _selectedServiceTypeIds.isEmpty
                ? 'Nenhum selecionado'
                : '${_selectedServiceTypeIds.length} selecionados',
            services: serviceTypes
                .map((t) => view.WorkerServiceSelectionViewData(
                      id: t.id,
                      label: t.name,
                      selected: _selectedServiceTypeIds.contains(t.id),
                    ))
                .toList(),
            tools: List.of(_tools),
          ),
        ));
      },
    );

    return view.WorkerProfileEditScreen(
      dataAsync: dataAsync,
      section: _section,
      onBack: () => context.pop(),
      onSectionBack: _backToOverview,
      onSignOut: _signOut,
      fullNameController: _fullNameController,
      phoneController: _phoneController,
      bioController: _bioController,
      hourlyRateController: _hourlyRateController,
      fullNameValidator: _fullNameValidator,
      phoneValidator: _phoneValidator,
      onChangePhoto: _pickAvatar,
      onOpenBaseLocation: () => _openSection(view.WorkerProfileEditSection.baseLocation),
      onOpenServicesAndTools: () =>
          _openSection(view.WorkerProfileEditSection.servicesAndTools),
      onOpenRatings: _openRatings,
      onSaveOverview: _saveOverview,
      addressSearchController: _addressSearchController,
      latitudeController: _latController,
      longitudeController: _lngController,
      onUseGps: _getLocation,
      onSubmitAddressSearch: _geocodeAddress,
      onToggleManualCoordinates: _toggleManualCoordinates,
      onRadiusChanged: _changeRadius,
      onSaveBaseLocation: _saveBaseLocation,
      serviceSearchController: _serviceSearchController,
      toolInputController: _toolController,
      onToggleService: _toggleService,
      onAddTool: _addTool,
      onRemoveTool: _removeTool,
      onSaveServicesAndTools: _saveServicesAndTools,
      onRetry: () => ref.invalidate(workerProfileProvider),
    );
  }
}
