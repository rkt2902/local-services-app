import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/geocoding_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/application/session_provider.dart';
import '../application/worker_providers.dart';
import '../data/worker_profile_model.dart';

class WorkerSetupScreen extends ConsumerStatefulWidget {
  const WorkerSetupScreen({super.key});

  @override
  ConsumerState<WorkerSetupScreen> createState() => _WorkerSetupScreenState();
}

class _WorkerSetupScreenState extends ConsumerState<WorkerSetupScreen> {
  final _addressSearchController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  File? _avatar;
  final List<String> _selectedServiceTypeIds = [];
  final int _radiusKm = 10;
  double? _baseLat;
  double? _baseLng;
  String _locationName = '';
  bool _loadingLocation = false;
  String? _locationError;
  bool _geocoding = false;
  bool _showAddressSearch = false;
  bool _showManualCoords = false;
  bool _saving = false;

  bool get _canContinue =>
      _avatar != null &&
      _selectedServiceTypeIds.isNotEmpty &&
      _baseLat != null &&
      _baseLng != null;

  @override
  void dispose() {
    _addressSearchController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
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
    if (picked != null) setState(() => _avatar = File(picked.path));
  }

  Future<void> _geocodeAddress() async {
    final text = _addressSearchController.text.trim();
    if (text.isEmpty) return;
    setState(() => _geocoding = true);
    try {
      final locations = await locationFromAddress(text);
      if (!mounted) return;
      if (locations.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Morada não encontrada.')));
        return;
      }
      final lat = locations.first.latitude;
      final lng = locations.first.longitude;
      setState(() {
        _baseLat = lat;
        _baseLng = lng;
        _showAddressSearch = false;
        _showManualCoords = false;
        _locationError = null;
      });
      GeocodingService.reverseGeocode(lat, lng).then((result) {
        if (!mounted || result == null) return;
        setState(() => _locationName = result.locationName);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao pesquisar morada.')));
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
        _showAddressSearch = false;
        _showManualCoords = false;
        _locationError = null;
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
      setState(() {
        _baseLat = position.latitude;
        _baseLng = position.longitude;
        _showAddressSearch = false;
        _locationError = null;
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

  Future<void> _save() async {
    if (!_canContinue) return;
    setState(() => _saving = true);
    try {
      final currentUser = ref.read(currentUserProvider)!;
      final profileData =
          await ref.read(authRepositoryProvider).fetchNameAndPhone(currentUser.id);
      if (profileData == null) {
        throw Exception(
            'Perfil de utilizador não encontrado. Tenta fazer login novamente.');
      }
      final repo = ref.read(workerRepositoryProvider);
      String? avatarUrl;
      if (_avatar != null) {
        avatarUrl = await repo.uploadAvatar(currentUser.id, _avatar!);
      }
      await repo.createProfile(WorkerProfile(
        profileId: currentUser.id,
        fullName: profileData.fullName,
        phone: profileData.phone,
        avatarUrl: avatarUrl,
        bio: null,
        defaultHourlyRate: null,
        radiusKm: _radiusKm,
        baseLat: _baseLat!,
        baseLng: _baseLng!,
        locationName: _locationName,
        tools: const [],
        serviceTypeIds: List.from(_selectedServiceTypeIds),
      ));
      if (!mounted) return;
      await ref.read(sessionStatusProvider.notifier).refresh();
      if (!mounted) return;
      context.go('/worker/home');
      ref.invalidate(workerProfileProvider);
    } catch (e) {
      debugPrint('[WorkerSetup] ${e.runtimeType}: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final serviceTypesAsync = ref.watch(serviceTypesProvider);
    final locationLabel = _locationName.isNotEmpty
        ? _locationName
        : (_baseLat != null
            ? '${_baseLat!.toStringAsFixed(4)}, ${_baseLng!.toStringAsFixed(4)}'
            : '');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 24, 0),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    if (context.canPop())
                      IconButton(
                        onPressed: context.pop,
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.textPrimary),
                      ),
                    Expanded(
                      child: Text(
                        'Configurar perfil',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Scrollable body ──────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Photo ─────────────────────────────────────────────
                    Center(
                      child: _WorkerPhotoSelector(
                        avatar: _avatar,
                        onPressed: _pickAvatar,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // ── Services ──────────────────────────────────────────
                    Text(
                      'Serviços que ofereço',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    serviceTypesAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Text(
                        'Erro ao carregar serviços: ${friendlyError(e)}',
                        style:
                            textTheme.bodyMedium?.copyWith(color: Colors.red),
                      ),
                      data: (types) => Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: types
                              .map((t) => WorkerServiceTypeChip(
                                    serviceTypeId: t.id,
                                    serviceTypeLabel: t.name,
                                    selected: _selectedServiceTypeIds
                                        .contains(t.id),
                                    onToggle: (id) => setState(() {
                                      if (_selectedServiceTypeIds
                                          .contains(id)) {
                                        _selectedServiceTypeIds.remove(id);
                                      } else {
                                        _selectedServiceTypeIds.add(id);
                                      }
                                    }),
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // ── Work area ─────────────────────────────────────────
                    Text(
                      'Zona de trabalho',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),

                    // Two location buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => setState(() =>
                                _showAddressSearch = !_showAddressSearch),
                            icon: const Icon(Icons.place_outlined, size: 18),
                            label: const Text('Inserir morada'),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              side:
                                  const BorderSide(color: AppColors.primary),
                              foregroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.input),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                _loadingLocation ? null : _getLocation,
                            icon: _loadingLocation
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.my_location_rounded,
                                    size: 18),
                            label: const Text('Usar GPS'),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              side:
                                  const BorderSide(color: AppColors.primary),
                              foregroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.input),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Address search (toggled by "Inserir morada")
                    if (_showAddressSearch) ...[
                      const SizedBox(height: AppSpacing.sm),
                      AppTextField(
                        controller: _addressSearchController,
                        label: 'Pesquisar morada',
                        keyboardType: TextInputType.streetAddress,
                        onFieldSubmitted: (_) => _geocodeAddress(),
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
                                icon: const Icon(Icons.search,
                                    color: AppColors.primary),
                                onPressed: _geocodeAddress,
                              ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      TextButton(
                        onPressed: () => setState(
                            () => _showManualCoords = !_showManualCoords),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primaryPressed,
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          alignment: Alignment.centerLeft,
                        ),
                        child: Text(
                          _showManualCoords
                              ? 'Ocultar coordenadas'
                              : 'Introduzir coordenadas manualmente',
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.primaryPressed,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_showManualCoords) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Expanded(
                              child: AppTextField(
                                controller: _latController,
                                label: 'Latitude',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true, signed: true),
                                onFieldSubmitted: (_) => _applyManualCoords(),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: AppTextField(
                                controller: _lngController,
                                label: 'Longitude',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true, signed: true),
                                onFieldSubmitted: (_) => _applyManualCoords(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],

                    // GPS error
                    if (_locationError != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _locationError!,
                        style:
                            textTheme.bodySmall?.copyWith(color: Colors.red),
                      ),
                    ],

                    // Location result card
                    if (_baseLat != null && _baseLng != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _WorkAreaResultCard(label: locationLabel),
                    ],

                    const SizedBox(height: AppSpacing.md),
                    const _IdentityVerificationNotice(),
                  ],
                ),
              ),
            ),

            // ── Bottom action ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
              child: PrimaryActionButton(
                label: 'Entrar na app',
                isLoading: _saving,
                onPressed: _canContinue ? _save : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Private widgets ────────────────────────────────────────────────────────────

class _WorkerPhotoSelector extends StatelessWidget {
  const _WorkerPhotoSelector({
    required this.avatar,
    required this.onPressed,
  });

  final File? avatar;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasPhoto = avatar != null;

    return Semantics(
      button: true,
      label: 'Adicionar foto de perfil',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Column(
          children: [
            SizedBox(
              width: 96,
              height: 92,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryContainer,
                      image: hasPhoto
                          ? DecorationImage(
                              image: FileImage(avatar!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: hasPhoto
                        ? null
                        : const Icon(Icons.grass_rounded,
                            size: 42, color: AppColors.primary),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 4,
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary,
                      ),
                      child: const Icon(Icons.photo_camera_outlined,
                          size: 17, color: AppColors.surface),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasPhoto ? 'Alterar foto' : 'Adicionar foto',
              style: textTheme.labelMedium?.copyWith(color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkerServiceTypeChip extends StatelessWidget {
  const WorkerServiceTypeChip({
    required this.serviceTypeId,
    required this.serviceTypeLabel,
    required this.selected,
    required this.onToggle,
    super.key,
  });

  final String serviceTypeId;
  final String serviceTypeLabel;
  final bool selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return FilterChip(
      selected: selected,
      onSelected: (_) => onToggle(serviceTypeId),
      showCheckmark: selected,
      checkmarkColor: AppColors.primary,
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primaryContainer,
      side: BorderSide(
        color: selected ? AppColors.primaryContainer : AppColors.divider,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      label: Text(
        serviceTypeLabel,
        style: textTheme.labelMedium?.copyWith(
          color: selected ? AppColors.primary : AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _WorkAreaResultCard extends StatelessWidget {
  const _WorkAreaResultCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.isEmpty ? 'Selecionar zona e raio' : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                color: label.isEmpty
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.location_on_outlined,
              color: AppColors.primary, size: 22),
        ],
      ),
    );
  }
}

class _IdentityVerificationNotice extends StatelessWidget {
  const _IdentityVerificationNotice();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.shield_outlined,
                size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'A verificação de identidade aumenta a '
              'confiança e as propostas aceites.',
              style: textTheme.labelMedium?.copyWith(
                color: AppColors.primaryPressed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
