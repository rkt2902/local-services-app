import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/services/geocoding_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_text_field.dart';

/// Localização escolhida em [JobLocationPicker].
class JobLocationValue {
  const JobLocationValue({
    required this.addressText,
    required this.addressAutoFilled,
    required this.locationArea,
    required this.lat,
    required this.lng,
  });

  final String addressText;

  /// `true` quando [addressText] veio do reverse geocoding do pin e não foi
  /// mexida à mão: ao mover o pin, é substituída.
  final bool addressAutoFilled;

  /// Localidade do pin, mostrada ao jardineiro em vez da morada exata até
  /// a proposta ser aceite (migration 0043).
  final String? locationArea;
  final double? lat;
  final double? lng;

  bool get hasPin => lat != null && lng != null;
}

/// Mapa + "Usar a minha localização" + campo de morada de um pedido.
///
/// Extraído do passo 2 do wizard (client_create_job_schedule_screen.dart)
/// para ser usado também em "Editar pedido". Guarda o estado internamente
/// e avisa o ecrã de cada mudança por [onChanged].
class JobLocationPicker extends StatefulWidget {
  const JobLocationPicker({
    required this.initial,
    required this.onChanged,
    this.staggerStartIndex = 0,
    this.title = 'Onde?',
    super.key,
  });

  final JobLocationValue initial;
  final ValueChanged<JobLocationValue> onChanged;

  /// Índice de [AppStaggeredEntrance] do primeiro elemento.
  final int staggerStartIndex;

  /// Título da secção, por cima do mapa.
  final String title;

  @override
  State<JobLocationPicker> createState() => _JobLocationPickerState();
}

class _JobLocationPickerState extends State<JobLocationPicker> {
  final _addressController = TextEditingController();
  final _mapController = MapController();

  LatLng? _pinPosition;
  bool _loadingLocation = false;
  bool _geocoding = false;
  String? _locationError;

  /// `true` quando o reverse geocoding do pin (GPS ou toque no mapa) não
  /// devolveu rua nenhuma: mostra um aviso em vez de inventar texto de
  /// morada. Só interessa enquanto o campo continuar vazio.
  bool _addressLookupFailed = false;

  String? _locationArea;

  /// `true` enquanto a morada do campo veio do pin e o utilizador não lhe
  /// mexeu: ao mover o pin é substituída. Escrita à mão nunca é tocada.
  bool _addressAutoFilled = false;

  /// Texto posto pelo geocoding; qualquer diferença vem do utilizador.
  String? _autoFilledText;

  /// Só a resposta do último pin conta: um toque rápido em dois sítios não
  /// pode deixar a morada/localidade do primeiro.
  int _geocodeRequest = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _addressController.text = initial.addressText;
    _addressAutoFilled = initial.addressAutoFilled;
    if (_addressAutoFilled) _autoFilledText = initial.addressText;
    _addressController.addListener(_onAddressChanged);
    _locationArea = initial.locationArea;
    if (initial.hasPin) _pinPosition = LatLng(initial.lat!, initial.lng!);
  }

  @override
  void dispose() {
    _addressController.removeListener(_onAddressChanged);
    _addressController.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged(JobLocationValue(
      addressText: _addressController.text.trim(),
      addressAutoFilled: _addressAutoFilled,
      locationArea: _locationArea,
      lat: _pinPosition?.latitude,
      lng: _pinPosition?.longitude,
    ));
  }

  void _onAddressChanged() {
    if (_addressAutoFilled && _addressController.text != _autoFilledText) {
      _addressAutoFilled = false;
    }
    _notify();
  }

  void _fillAddressFromPin(String text) {
    _autoFilledText = text;
    _addressAutoFilled = true;
    _addressController.text = text;
  }

  Future<void> _geocode() async {
    final text = _addressController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _geocoding = true;
      _addressLookupFailed = false;
    });
    try {
      final found = await GeocodingService.searchAddress(text);
      if (!mounted) return;
      if (found == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Morada não encontrada. Tenta ser mais específico.'),
        ));
        return;
      }
      final latlng = LatLng(found.lat, found.lng);
      setState(() => _pinPosition = latlng);
      _mapController.move(latlng, 14);
      _notify();
      // Só para atualizar a localidade (o texto escrito não é tocado).
      _reverseGeocodePin(latlng.latitude, latlng.longitude);
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
    _notify();
    _reverseGeocodePin(point.latitude, point.longitude);
  }

  /// Preenche a morada a partir do pin quando o campo está vazio ou ainda
  /// tem a morada automática de um pin anterior; nunca sobrescreve texto
  /// escrito à mão. A localidade antiga apaga-se logo: pertence ao pin
  /// anterior. Se o geocoding falhar, NÃO inventa texto de morada: mostra
  /// um aviso de que o pin ficou guardado mas a rua não foi identificada.
  Future<void> _reverseGeocodePin(double lat, double lng) async {
    final request = ++_geocodeRequest;
    setState(() {
      _addressLookupFailed = false;
      _locationArea = null;
    });
    _notify();
    final result = await GeocodingService.reverseGeocode(lat, lng);
    if (!mounted || request != _geocodeRequest) return;
    // A localidade guarda-se sempre que o geocoding responde, mesmo que a
    // morada tenha sido escrita à mão.
    if (result != null) _locationArea = result.locationName;
    final canReplace = _addressController.text.isEmpty || _addressAutoFilled;
    if (!canReplace) {
      _notify();
      return;
    }
    setState(() {
      if (result != null) {
        _fillAddressFromPin(result.addressText);
      } else {
        // A morada automática era do pin anterior: já não serve.
        if (_addressAutoFilled) {
          _addressAutoFilled = false;
          _addressController.clear();
        }
        _addressLookupFailed = true;
      }
    });
    _notify();
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
      final latlng = LatLng(position.latitude, position.longitude);
      setState(() => _pinPosition = latlng);
      _mapController.move(latlng, 14);
      _notify();
      // Aguardado de propósito: o spinner fica aceso até a morada estar
      // resolvida, para não se poder continuar com o campo ainda vazio.
      await _reverseGeocodePin(position.latitude, position.longitude);
    } catch (e) {
      if (!mounted) return;
      setState(
          () => _locationError = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final start = widget.staggerStartIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppStaggeredEntrance(
          index: start,
          child: Text(
            widget.title,
            style:
                textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppStaggeredEntrance(
          // Chave estável: sem ela, um bloco condicional acima (ex.: o
          // campo de data a aparecer/desaparecer) pode fazer o Flutter
          // recriar o FlutterMap com um `_mapController.move` pendente, e
          // o flutter_map lança "You need to have the FlutterMap widget
          // rendered at least once before using the MapController."
          key: const ValueKey('job_location_map'),
          index: start + 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: SizedBox(
              height: AppSizes.jobMapHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter:
                            _pinPosition ?? const LatLng(38.7169, -9.1399),
                        initialZoom: 14,
                        onTap: _onMapTap,
                      ),
                      children: [
                        // TODO(mapa-estilizado): tile "standard" da OSM de
                        // propósito (2026-09). Um mapa nativo com estilo de
                        // marca exige o SDK do Google Maps (projeto,
                        // faturação e API key): decisão de produto e
                        // orçamento para mais tarde.
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
                                width: AppSizes.mapPin,
                                height: AppSizes.mapPin,
                                alignment: Alignment.topCenter,
                                child: const Icon(
                                  Icons.location_on_outlined,
                                  color: AppColors.primary,
                                  size: AppSizes.mapPin,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  // O pin muda com um toque no mapa (o flutter_map não
                  // arrasta marcadores sem um plugin extra).
                  Positioned(
                    top: AppSpacing.xs,
                    right: AppSpacing.xs,
                    child: _MapPill(
                      child: Text(
                        'Toca no mapa',
                        style: textTheme.labelMedium
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                  Positioned(
                    left: AppSpacing.xs,
                    bottom: AppSpacing.xs,
                    child: _MapPill(
                      onPressed: _loadingLocation ? null : _getLocation,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_loadingLocation)
                            const SizedBox.square(
                              dimension: AppSizes.inlineSpinner,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            const Icon(
                              Icons.my_location_rounded,
                              size: AppSizes.inlineIcon,
                              color: AppColors.primary,
                            ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            _loadingLocation
                                ? 'A localizar...'
                                : 'Usar a minha localização',
                            style: textTheme.labelMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_locationError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              _locationError!,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        AppStaggeredEntrance(
          index: start + 2,
          child: AppTextField(
            controller: _addressController,
            label: 'Morada / referência',
            hintText: 'Ex: Rua das Flores 23, portão azul',
            keyboardType: TextInputType.streetAddress,
            textInputAction: TextInputAction.search,
            onFieldSubmitted: (_) => _geocode(),
            suffixIcon: _geocoding
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: SizedBox.square(
                      dimension: AppSizes.inlineSpinner,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Procurar morada',
                    icon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.primary,
                    ),
                    onPressed: _geocode,
                  ),
          ),
        ),
        if (_addressLookupFailed && _addressController.text.isEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Não foi possível identificar a rua, mas a localização foi '
            'guardada. Podes escrever a morada à mão acima.',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Pílula branca por cima do mapa (dica ou botão).
class _MapPill extends StatelessWidget {
  const _MapPill({required this.child, this.onPressed});

  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: child,
        ),
      ),
    );
  }
}
