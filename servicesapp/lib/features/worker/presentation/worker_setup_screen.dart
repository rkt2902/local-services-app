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
import '../../../core/theme/app_status_color.dart';
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
  final _bioController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  final _toolController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  int _radiusKm = 10;
  double? _baseLat;
  double? _baseLng;
  bool _loadingLocation = false;
  String? _locationError;
  File? _avatar;
  final List<String> _tools = [];
  final List<String> _selectedServiceTypeIds = [];
  bool _saving = false;
  String _locationName = '';
  bool _geocoding = false;
  bool _showManualCoords = false;
  final _addressSearchController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  @override
  void dispose() {
    _bioController.dispose();
    _hourlyRateController.dispose();
    _toolController.dispose();
    _addressSearchController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
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
            'Permissão de localização negada permanentemente. Ativa nas definições.');
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
    if (picked != null) setState(() => _avatar = File(picked.path));
  }

  void _addTool() {
    final tool = _toolController.text.trim();
    if (tool.isEmpty) return;
    setState(() {
      _tools.add(tool);
      _toolController.clear();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_baseLat == null || _baseLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Obtém a tua localização primeiro.'),
        backgroundColor: Colors.red,
      ));
      return;
    }
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
        bio: _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
        defaultHourlyRate: double.tryParse(_hourlyRateController.text.trim()),
        radiusKm: _radiusKm,
        baseLat: _baseLat!,
        baseLng: _baseLng!,
        locationName: _locationName,
        tools: _tools,
        serviceTypeIds: _selectedServiceTypeIds,
      ));
      if (!mounted) return;
      await ref.read(sessionStatusProvider.notifier).refresh();
      if (!mounted) return;
      context.go('/worker/home');
      ref.invalidate(workerProfileProvider);
    } catch (e) {
      debugPrint('[BUG1_DIAG] ${e.runtimeType}: $e');
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

    final sectionTitleStyle = textTheme.titleLarge?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 14, 0),
              child: Row(
                children: [
                  if (context.canPop())
                    IconButton(
                      onPressed: context.pop,
                      icon: const Icon(Icons.arrow_back_rounded),
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

            // ── Form ──────────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Photo
                      Center(
                        child: _PhotoSection(
                          avatar: _avatar,
                          onPick: _pickAvatar,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Preenche o teu perfil para começares a receber pedidos.',
                        style: textTheme.bodyMedium
                            ?.copyWith(color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),

                      // ── Bio ───────────────────────────────────────────
                      const SizedBox(height: 28),
                      Text('Apresentação', style: sectionTitleStyle),
                      const SizedBox(height: 12),
                      AppTextField(
                        controller: _bioController,
                        label: 'Apresentação (opcional)',
                        maxLines: 5,
                        minLines: 3,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                      ),

                      // ── Localização ───────────────────────────────────
                      const SizedBox(height: 28),
                      Text('Localização base', style: sectionTitleStyle),
                      const SizedBox(height: 12),

                      if (_baseLat != null && _baseLng != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppStatusColor.success.background,
                            borderRadius:
                                BorderRadius.circular(AppRadius.input),
                            border: Border.all(
                              color: AppStatusColor.success.foreground
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  color: AppStatusColor.success.foreground,
                                  size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _locationName.isNotEmpty
                                      ? _locationName
                                      : '${_baseLat!.toStringAsFixed(4)}, '
                                          '${_baseLng!.toStringAsFixed(4)}',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: AppStatusColor.success.foreground,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      if (_locationError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _locationError!,
                            style: textTheme.bodySmall
                                ?.copyWith(color: Colors.red),
                          ),
                        ),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _loadingLocation ? null : _getLocation,
                          icon: _loadingLocation
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.my_location_rounded),
                          label: Text(
                            _baseLat == null
                                ? 'Usar a minha localização'
                                : 'Atualizar localização',
                            style: textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: AppColors.primary),
                            foregroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.input),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

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
                      const SizedBox(height: 4),

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
                        const SizedBox(height: 8),
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
                            const SizedBox(width: 12),
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

                      // ── Raio ──────────────────────────────────────────
                      const SizedBox(height: 28),
                      Text('Raio de atuação: $_radiusKm km',
                          style: sectionTitleStyle),
                      Slider(
                        value: _radiusKm.toDouble(),
                        min: 1,
                        max: 50,
                        divisions: 49,
                        label: '$_radiusKm km',
                        onChanged: (v) =>
                            setState(() => _radiusKm = v.round()),
                      ),

                      // ── Preço/hora ────────────────────────────────────
                      const SizedBox(height: 4),
                      AppTextField(
                        controller: _hourlyRateController,
                        label: 'Preço/hora (€) — opcional',
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),

                      // ── Serviços ──────────────────────────────────────
                      const SizedBox(height: 28),
                      Text('Serviços que ofereço', style: sectionTitleStyle),
                      const SizedBox(height: 12),
                      serviceTypesAsync.when(
                        loading: () => const Center(
                            child: CircularProgressIndicator()),
                        error: (e, _) => Text(
                          'Erro ao carregar serviços: ${friendlyError(e)}',
                          style: textTheme.bodyMedium
                              ?.copyWith(color: Colors.red),
                        ),
                        data: (types) => Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: types.map((t) {
                              final selected =
                                  _selectedServiceTypeIds.contains(t.id);
                              return FilterChip(
                                selected: selected,
                                onSelected: (v) => setState(() {
                                  if (v) {
                                    _selectedServiceTypeIds.add(t.id);
                                  } else {
                                    _selectedServiceTypeIds.remove(t.id);
                                  }
                                }),
                                label: Text(t.name),
                                showCheckmark: true,
                                selectedColor: AppColors.primaryContainer,
                                checkmarkColor: AppColors.primaryPressed,
                                backgroundColor: AppColors.surface,
                                side: BorderSide(
                                  color: selected
                                      ? Colors.transparent
                                      : AppColors.divider,
                                ),
                                labelStyle: textTheme.bodyMedium?.copyWith(
                                  color: selected
                                      ? AppColors.primaryPressed
                                      : AppColors.textPrimary,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppRadius.pill),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),

                      // ── Ferramentas ───────────────────────────────────
                      const SizedBox(height: 28),
                      Text('Ferramentas', style: sectionTitleStyle),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _toolController,
                              label: 'Adicionar ferramenta',
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _addTool(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filled(
                            onPressed: _addTool,
                            icon: const Icon(Icons.add),
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.input),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_tools.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _tools
                              .map((t) => Chip(
                                    label: Text(t),
                                    onDeleted: () =>
                                        setState(() => _tools.remove(t)),
                                    backgroundColor:
                                        AppColors.primaryContainer,
                                    labelStyle:
                                        textTheme.bodyMedium?.copyWith(
                                      color: AppColors.primaryPressed,
                                    ),
                                    deleteIconColor: AppColors.primaryPressed,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppRadius.pill),
                                      side: BorderSide.none,
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),

            // ── Save button ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
              child: PrimaryActionButton(
                label: 'Entrar na app',
                isLoading: _saving,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Photo section ─────────────────────────────────────────────────────────────

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({required this.avatar, required this.onPick});

  final File? avatar;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasPhoto = avatar != null;

    return Column(
      children: [
        GestureDetector(
          onTap: onPick,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 52,
                backgroundColor: AppColors.primaryContainer,
                backgroundImage:
                    hasPhoto ? FileImage(avatar!) as ImageProvider : null,
                child: hasPhoto
                    ? null
                    : const Icon(Icons.person_rounded,
                        size: 52, color: AppColors.primary),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hasPhoto ? 'Alterar foto' : 'Adicionar foto',
          style: textTheme.bodyMedium?.copyWith(
            color: AppColors.primaryPressed,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
