import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/services/geocoding_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/utils/error_utils.dart';
import '../../../../core/widgets/address_suggestions_list.dart';
import '../../../../core/widgets/app_filter_chip.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../application/admin_providers.dart';
import '../../data/admin_partner_models.dart';
import 'admin_partner_marker.dart';

/// Abre o editor de uma gasolineira ([partner] `null` = nova). Devolve
/// `true` quando gravou.
Future<bool?> showAdminPartnerEditor(
  BuildContext context, {
  AdminPartnerLocation? partner,
}) => showDialog<bool>(
  context: context,
  builder: (_) => AdminPartnerEditor(partner: partner),
);

/// Nome, marca, estado, localização (pesquisa de morada ou tocar no
/// mapa) e notas. Grava com `admin_save_partner_location`.
class AdminPartnerEditor extends ConsumerStatefulWidget {
  const AdminPartnerEditor({this.partner, this.showTiles = true, super.key});

  final AdminPartnerLocation? partner;

  /// `false` nos testes (sem rede).
  final bool showTiles;

  @override
  ConsumerState<AdminPartnerEditor> createState() => _AdminPartnerEditorState();
}

class _AdminPartnerEditorState extends ConsumerState<AdminPartnerEditor> {
  late final _name = TextEditingController(text: widget.partner?.name);
  late final _brand = TextEditingController(text: widget.partner?.brand);
  late final _address = TextEditingController(text: widget.partner?.address);
  late final _locality = TextEditingController(text: widget.partner?.locality);
  late final _notes = TextEditingController(text: widget.partner?.notes);
  final _map = MapController();
  late AdminPartnerStatus _status =
      widget.partner?.status ?? AdminPartnerStatus.prospect;
  late LatLng? _point = widget.partner == null
      ? null
      : LatLng(widget.partner!.lat, widget.partner!.lng);
  List<AddressSuggestion> _suggestions = const [];
  bool _searching = false;
  bool _searched = false;
  Timer? _debounce;
  bool _saving = false;
  String? _error;

  static const _portugal = LatLng(39.6, -8.0);

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _brand.dispose();
    _address.dispose();
    _locality.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _search(String text) {
    _debounce?.cancel();
    if (text.trim().length < 3) {
      setState(() {
        _suggestions = const [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _searching = true);
      List<AddressSuggestion> found = const [];
      try {
        found = await GeocodingService.suggestAddresses(text, limit: 5);
      } catch (_) {
        // Sem rede: fica o mapa.
      }
      if (!mounted) return;
      setState(() {
        _suggestions = found;
        _searching = false;
        _searched = true;
      });
    });
  }

  void _pick(AddressSuggestion s) {
    final point = LatLng(s.lat, s.lng);
    setState(() {
      _address.text = s.fullText;
      if (_locality.text.trim().isEmpty && s.locality != null) {
        _locality.text = s.locality!;
      }
      _point = point;
      _suggestions = const [];
      _searched = false;
    });
    _moveMap(point);
  }

  void _moveMap(LatLng point) {
    try {
      _map.move(point, 15);
    } catch (_) {
      // O mapa ainda não está pronto: o centro inicial já é este.
    }
  }

  bool get _valid {
    final p = _point;
    final name = _name.text.trim();
    return name.length >= 2 &&
        name.length <= 80 &&
        p != null &&
        adminInPortugal(p.latitude, p.longitude);
  }

  Future<void> _save() async {
    final p = _point!;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(adminRepositoryProvider)
          .savePartner(
            AdminPartnerDraft(
              id: widget.partner?.id,
              name: _name.text,
              brand: _brand.text,
              status: _status,
              address: _address.text,
              locality: _locality.text,
              notes: _notes.text,
              lat: p.latitude,
              lng: p.longitude,
            ),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final point = _point;
    final outside =
        point != null && !adminInPortugal(point.latitude, point.longitude);
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppSizes.adminEditorMaxWidth,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.partner == null
                    ? 'Nova gasolineira'
                    : 'Alterar ${widget.partner!.name}',
                style: textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _name,
                label: 'Nome',
                hintText: 'Ex.: Posto da Avenida',
                maxLength: 80,
              ),
              const SizedBox(height: AppSpacing.xs),
              AppTextField(
                controller: _brand,
                label: 'Marca (opcional)',
                maxLength: 60,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Estado',
                style: textTheme.labelLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final s in AdminPartnerStatus.values)
                    AppFilterChip(
                      label: s.label,
                      selected: _status == s,
                      onPressed: () => setState(() => _status = s),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _address,
                onChanged: _search,
                decoration: const InputDecoration(
                  labelText: 'Morada',
                  hintText: 'Pesquisa a morada ou o nome do posto',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              AddressSuggestionsList(
                suggestions: _suggestions,
                loading: _searching,
                onSelected: _pick,
                emptyHint: _searched ? addressNotFoundHint : null,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                point == null
                    ? 'Toca no mapa no sítio do posto, ou escolhe uma morada.'
                    : 'Toca no mapa para acertar o sítio.',
                style: textTheme.bodySmall?.copyWith(
                  color: outside
                      ? AppStatusColor.cancelled.foreground
                      : AppColors.textSecondary,
                ),
              ),
              if (outside)
                Text(
                  'Tem de ficar em Portugal.',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppStatusColor.cancelled.foreground,
                  ),
                ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                height: AppSizes.adminPartnerMapHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  child: FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: point ?? _portugal,
                      initialZoom: point == null ? 6 : 15,
                      onTap: (_, p) => setState(() => _point = p),
                    ),
                    children: [
                      if (widget.showTiles)
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'pt.projardim.app',
                        ),
                      if (point != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: point,
                              width: AppSizes.adminPartnerMarker,
                              height: AppSizes.adminPartnerMarker,
                              child: AdminPartnerMarker(status: _status),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: _locality,
                label: 'Localidade (opcional)',
                maxLength: 60,
              ),
              const SizedBox(height: AppSpacing.xs),
              AppTextField(
                controller: _notes,
                label: 'Notas (opcional, só o suporte vê)',
                hintText: 'Contacto, condições, data da conversa',
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _error!,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppStatusColor.cancelled.foreground,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('Voltar'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  FilledButton(
                    onPressed: _valid && !_saving ? _save : null,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: AppSizes.inlineSpinner,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Gravar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
