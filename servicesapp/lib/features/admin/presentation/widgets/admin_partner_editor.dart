import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/services/geocoding_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/utils/error_utils.dart';
import '../../../../core/utils/picked_photo.dart';
import '../../../../core/widgets/address_suggestions_list.dart';
import '../../../../core/widgets/app_date_picker.dart';
import '../../../../core/widgets/app_filter_chip.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../partners/data/partner_model.dart';
import '../../../partners/presentation/widgets/partner_banner_card.dart';
import '../../../partners/presentation/widgets/partner_detail_view.dart';
import '../../application/admin_providers.dart';
import '../../data/admin_partner_models.dart';
import 'admin_partner_marker.dart';

/// Abre o editor de um parceiro ([partner] `null` = novo). Devolve `true`
/// quando gravou.
Future<bool?> showAdminPartnerEditor(
  BuildContext context, {
  AdminPartner? partner,
}) => showDialog<bool>(
  context: context,
  builder: (_) => AdminPartnerEditor(partner: partner),
);

/// Tipos de foto que o bucket `partner-images` aceita (0082).
const _imageTypes = {'image/jpeg', 'image/png', 'image/webp'};

/// Todos os campos de um parceiro. Tudo menos o nome é opcional: o que
/// ficar em branco não aparece na app. Grava com `admin_save_partner`; a
/// foto vai para o bucket `partner-images` ao gravar.
class AdminPartnerEditor extends ConsumerStatefulWidget {
  const AdminPartnerEditor({this.partner, this.showTiles = true, super.key});

  final AdminPartner? partner;

  /// `false` nos testes (sem rede).
  final bool showTiles;

  @override
  ConsumerState<AdminPartnerEditor> createState() => _AdminPartnerEditorState();
}

class _AdminPartnerEditorState extends ConsumerState<AdminPartnerEditor> {
  AdminPartner? get _p => widget.partner;

  late final _name = TextEditingController(text: _p?.name);
  late final _brand = TextEditingController(text: _p?.brand);
  late final _headline = TextEditingController(text: _p?.headline);
  late final _description = TextEditingController(text: _p?.description);
  late final _code = TextEditingController(text: _p?.discountCode);
  late final _barcode = TextEditingController(text: _p?.barcodeValue);
  late final _qr = TextEditingController(text: _p?.qrValue);
  late final _link = TextEditingController(text: _p?.linkUrl);
  late final _linkLabel = TextEditingController(text: _p?.linkLabel);
  late final _terms = TextEditingController(text: _p?.terms);
  late final _sort = TextEditingController(text: '${_p?.sortOrder ?? 100}');
  late final _address = TextEditingController(text: _p?.address);
  late final _locality = TextEditingController(text: _p?.locality);
  late final _notes = TextEditingController(text: _p?.notes);
  late final _controllers = [
    _name,
    _brand,
    _headline,
    _description,
    _code,
    _barcode,
    _qr,
    _link,
    _linkLabel,
    _terms,
    _sort,
    _address,
    _locality,
    _notes,
  ];
  final _map = MapController();

  late PartnerKind _kind = _p?.kind ?? PartnerKind.fuelStation;
  late AdminPartnerStatus _status = _p?.status ?? AdminPartnerStatus.prospect;
  late PartnerBarcodeFormat _barcodeFormat =
      _p?.barcodeFormat ?? PartnerBarcodeFormat.code128;
  late bool _visibleInApp = _p?.visibleInApp ?? false;
  late bool _proPlusOnly = _p?.proPlusOnly ?? true;
  late DateTime? _validUntil = _p?.validUntil;
  late LatLng? _point = _p?.hasLocation == true
      ? LatLng(_p!.lat!, _p!.lng!)
      : null;

  /// Foto atual gravada (`null` depois de "Tirar foto").
  late String? _imagePath = _p?.imagePath;

  /// Foto nova escolhida, ainda por enviar.
  XFile? _picked;
  String? _photoError;

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
    for (final c in _controllers) {
      c.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Localização ──

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

  // ── Foto ──

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: webPickMaxWidth,
      imageQuality: webPickImageQuality,
    );
    if (file == null || !mounted) return;
    setState(() {
      _picked = file;
      _photoError = _imageTypes.contains(pickedPhotoContentType(file))
          ? null
          : 'Usa uma foto JPEG, PNG ou WebP.';
    });
  }

  void _removePhoto() => setState(() {
    _picked = null;
    _imagePath = null;
    _photoError = null;
  });

  ImageProvider? get _photoPreview {
    final picked = _picked;
    if (picked != null) return pickedPhotoImage(picked);
    final url = partnerImageUrl(_imagePath);
    return url == null ? null : NetworkImage(url);
  }

  // ── Validação e gravação ──

  int? get _sortValue {
    final v = int.tryParse(_sort.text.trim());
    return v != null && v >= 0 && v <= 1000 ? v : null;
  }

  String? get _barcodeError => adminBarcodeError(_barcode.text, _barcodeFormat);
  String? get _linkError => adminLinkError(_link.text);
  bool get _outside {
    final p = _point;
    return p != null && !adminInPortugal(p.latitude, p.longitude);
  }

  bool get _valid {
    final name = _name.text.trim();
    return name.length >= 2 &&
        name.length <= 80 &&
        !_outside &&
        _barcodeError == null &&
        _linkError == null &&
        _photoError == null &&
        _sortValue != null;
  }

  AdminPartnerDraft _draft({String? imagePath}) => AdminPartnerDraft(
    id: _p?.id,
    name: _name.text,
    status: _status,
    kind: _kind,
    lat: _point?.latitude,
    lng: _point?.longitude,
    brand: _brand.text,
    headline: _headline.text,
    description: _description.text,
    imagePath: imagePath ?? _imagePath,
    discountCode: _code.text,
    barcodeValue: _barcode.text,
    barcodeFormat: _barcodeFormat,
    qrValue: _qr.text,
    linkUrl: _link.text,
    linkLabel: _linkLabel.text,
    terms: _terms.text,
    validUntil: _validUntil,
    visibleInApp: _visibleInApp,
    proPlusOnly: _proPlusOnly,
    sortOrder: _sortValue ?? 100,
    address: _address.text,
    locality: _locality.text,
    notes: _notes.text,
  );

  Future<void> _save() async {
    final repo = ref.read(adminRepositoryProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    String? uploaded;
    try {
      final picked = _picked;
      if (picked != null) {
        final photo = await photoBytesForUpload(picked);
        uploaded = await repo.uploadPartnerImage(
          folder: _p?.id ?? 'novo',
          bytes: photo.bytes,
          contentType: photo.contentType,
        );
      }
      await repo.savePartner(_draft(imagePath: uploaded));
      // A foto antiga só se apaga depois de gravar (trocada ou tirada).
      final old = _p?.imagePath;
      if (old != null && old != (uploaded ?? _imagePath)) {
        await repo.removePartnerImage(old);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (uploaded != null) await repo.removePartnerImage(uploaded);
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Future<void> _pickValidUntil() async {
    final now = DateTime.now();
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _validUntil ?? now.add(const Duration(days: 90)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) setState(() => _validUntil = picked);
  }

  void _preview() {
    final partner = _draft().toPreview();
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
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
                const _Label('Na lista'),
                PartnerBannerCard(
                  partner: partner,
                  image: _photoPreview,
                  onTap: () {},
                ),
                const SizedBox(height: AppSpacing.lg),
                const _Label('Ao abrir (como um profissional Pro+ o vê)'),
                PartnerDetailView(
                  partner: partner,
                  bannerImage: _photoPreview,
                  showMapTiles: widget.showTiles,
                  onCopyCode: (_) {},
                  onOpenLink: (_) {},
                ),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text('Fechar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final point = _point;
    final errorStyle = textTheme.bodySmall?.copyWith(
      color: AppStatusColor.cancelled.foreground,
    );
    final hintStyle = textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
    );
    final photo = _photoPreview;
    final notShown = _visibleInApp && _status != AdminPartnerStatus.active;
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
                _p == null ? 'Novo parceiro' : 'Alterar ${_p!.name}',
                style: textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Só o nome é obrigatório. O que ficar em branco não aparece '
                'na app.',
                style: hintStyle,
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
              const _Label('Tipo'),
              _Chips(
                children: [
                  for (final k in PartnerKind.values)
                    AppFilterChip(
                      label: k.label,
                      selected: _kind == k,
                      onPressed: () => setState(() => _kind = k),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const _Label('Estado'),
              _Chips(
                children: [
                  for (final s in AdminPartnerStatus.values)
                    AppFilterChip(
                      label: s.label,
                      selected: _status == s,
                      onPressed: () => setState(() => _status = s),
                    ),
                ],
              ),

              // ── Na app ──
              const _SectionTitle('Na app dos profissionais'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _visibleInApp,
                onChanged: (v) => setState(() => _visibleInApp = v),
                title: const Text('Mostrar na tab Parceiros'),
                subtitle: Text(
                  notShown
                      ? 'Só aparece quando o estado for "Parceiro".'
                      : 'Aparece aos profissionais quando o estado é '
                            '"Parceiro" e está dentro da validade.',
                  style: notShown ? errorStyle : hintStyle,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _proPlusOnly,
                onChanged: (v) => setState(() => _proPlusOnly = v),
                title: const Text('Códigos só para o Pro+'),
                subtitle: Text(
                  'Quem não é Pro+ vê o parceiro, mas não o código de '
                  'desconto, o código de barras nem o QR.',
                  style: hintStyle,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              const _Label('Foto do banner (opcional)'),
              if (photo != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  child: SizedBox(
                    height: AppSizes.adminPartnerPhoto,
                    child: Image(image: photo, fit: BoxFit.cover),
                  ),
                ),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  TextButton.icon(
                    onPressed: _saving ? null : _pickPhoto,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(photo == null ? 'Escolher foto' : 'Trocar'),
                  ),
                  if (photo != null)
                    TextButton.icon(
                      onPressed: _saving ? null : _removePhoto,
                      icon: const Icon(Icons.hide_image_outlined),
                      label: const Text('Tirar foto'),
                    ),
                ],
              ),
              if (_photoError != null) Text(_photoError!, style: errorStyle),
              const SizedBox(height: AppSpacing.xs),
              AppTextField(
                controller: _headline,
                label: 'Frase do banner (opcional)',
                hintText: 'Ex.: 10% de desconto em combustível',
                maxLength: 80,
              ),
              const SizedBox(height: AppSpacing.xs),
              AppTextField(
                controller: _description,
                label: 'Descrição (opcional)',
                maxLength: 2000,
                minLines: 3,
                maxLines: 8,
                textInputAction: TextInputAction.newline,
              ),
              const SizedBox(height: AppSpacing.xs),
              AppTextField(
                controller: _code,
                label: 'Código de desconto (opcional)',
                hintText: 'Ex.: PROJARDIM10',
                maxLength: 40,
              ),
              const SizedBox(height: AppSpacing.xs),
              AppTextField(
                controller: _barcode,
                label: 'Código de barras (opcional)',
                hintText: 'O número ou texto do código',
                maxLength: 80,
              ),
              _Chips(
                children: [
                  for (final f in PartnerBarcodeFormat.values)
                    AppFilterChip(
                      label: f.label,
                      selected: _barcodeFormat == f,
                      onPressed: () => setState(() => _barcodeFormat = f),
                    ),
                ],
              ),
              if (_barcodeError != null)
                Text(_barcodeError!, style: errorStyle),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: _qr,
                label: 'QR da promoção (opcional)',
                hintText: 'Texto ou link que o QR leva',
                maxLength: 500,
              ),
              const SizedBox(height: AppSpacing.xs),
              AppTextField(
                controller: _link,
                label: 'Link (opcional)',
                hintText: 'https://',
                keyboardType: TextInputType.url,
                maxLength: 500,
              ),
              if (_linkError != null) Text(_linkError!, style: errorStyle),
              if (_link.text.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                AppTextField(
                  controller: _linkLabel,
                  label: 'Texto do botão do link (opcional)',
                  hintText: 'Abrir o site',
                  maxLength: 40,
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              AppTextField(
                controller: _terms,
                label: 'Condições (opcional)',
                hintText: 'Ex.: Não acumula com outras promoções.',
                maxLength: 1000,
                minLines: 2,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _validUntil == null
                          ? 'Sem data de fim'
                          : 'Válido até '
                                '${DateFormat('dd/MM/yyyy').format(_validUntil!)}',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _pickValidUntil,
                    child: Text(
                      _validUntil == null ? 'Pôr data de fim' : 'Mudar',
                    ),
                  ),
                  if (_validUntil != null)
                    IconButton(
                      tooltip: 'Tirar a data de fim',
                      onPressed: () => setState(() => _validUntil = null),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              AppTextField(
                controller: _sort,
                label: 'Ordem na lista',
                helperText:
                    'Os números mais baixos aparecem primeiro (0 a 1000).',
                keyboardType: TextInputType.number,
              ),
              if (_sortValue == null)
                Text('Escreve um número de 0 a 1000.', style: errorStyle),

              // ── Localização ──
              const _SectionTitle('Localização (opcional)'),
              Text(
                'Com localização, o parceiro aparece no Mapa do painel e no '
                'ecrã dele na app.',
                style: hintStyle,
              ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _address,
                onChanged: _search,
                decoration: const InputDecoration(
                  labelText: 'Morada',
                  hintText: 'Pesquisa a morada ou o nome do sítio',
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      point == null
                          ? 'Toca no mapa no sítio do parceiro, ou escolhe '
                                'uma morada.'
                          : 'Toca no mapa para acertar o sítio.',
                      style: _outside ? errorStyle : hintStyle,
                    ),
                  ),
                  if (point != null)
                    TextButton(
                      onPressed: () => setState(() => _point = null),
                      child: const Text('Tirar do mapa'),
                    ),
                ],
              ),
              if (_outside)
                Text('Tem de ficar em Portugal.', style: errorStyle),
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
                              child: AdminPartnerMarker(
                                status: _status,
                                kind: _kind,
                              ),
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

              // ── Só o suporte ──
              const _SectionTitle('Só para o suporte'),
              AppTextField(
                controller: _notes,
                label: 'Notas (opcional, não aparecem na app)',
                hintText: 'Contacto, condições, data da conversa',
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(_error!, style: errorStyle),
              ],
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  OutlinedButton.icon(
                    onPressed: _name.text.trim().length >= 2 ? _preview : null,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Ver como na app'),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('Voltar'),
                  ),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(color: AppColors.textPrimary),
    ),
  );
}

class _Chips extends StatelessWidget {
  const _Chips({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.xs,
    runSpacing: AppSpacing.xs,
    children: children,
  );
}
