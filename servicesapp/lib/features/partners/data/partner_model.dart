import 'package:flutter/material.dart';

import '../../../core/config/supabase_config.dart';

/// Tipos de parceiro (iguais à BD, `partners.kind`).
enum PartnerKind {
  fuelStation('fuel_station', 'Gasolineira', Icons.local_gas_station_rounded),
  gardenStore(
    'garden_store',
    'Loja de jardinagem',
    Icons.local_florist_rounded,
  ),
  equipment('equipment', 'Máquinas e ferramentas', Icons.handyman_rounded),
  services('services', 'Serviços', Icons.miscellaneous_services_rounded),
  other('other', 'Outro', Icons.storefront_rounded);

  const PartnerKind(this.value, this.label, this.icon);

  final String value;
  final String label;
  final IconData icon;

  static PartnerKind fromValue(String? v) =>
      values.firstWhere((k) => k.value == v, orElse: () => PartnerKind.other);
}

/// Formato do código de barras (`partners.barcode_format`).
enum PartnerBarcodeFormat {
  code128('code128', 'Code 128'),
  ean13('ean13', 'EAN-13');

  const PartnerBarcodeFormat(this.value, this.label);

  final String value;
  final String label;

  static PartnerBarcodeFormat fromValue(String? v) =>
      v == 'ean13' ? PartnerBarcodeFormat.ean13 : PartnerBarcodeFormat.code128;
}

String? _text(Object? v) =>
    v is String && v.trim().isNotEmpty ? v.trim() : null;

/// URL público da foto de um parceiro (bucket `partner-images`). `null`
/// sem foto ou sem `SUPABASE_URL` (testes).
String? partnerImageUrl(String? path, {String? supabaseUrl}) {
  final base = supabaseUrl ?? SupabaseConfig.url;
  if (path == null || path.isEmpty || base.isEmpty) return null;
  final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return '$root/storage/v1/object/public/partner-images/$path';
}

/// Um parceiro como a app o mostra (`get_partners`, 0082). Todos os
/// campos menos o nome são opcionais: o ecrã só mostra o que existe.
class Partner {
  const Partner({
    required this.id,
    required this.name,
    this.kind = PartnerKind.other,
    this.brand,
    this.headline,
    this.description,
    this.imagePath,
    this.discountCode,
    this.barcodeValue,
    this.barcodeFormat = PartnerBarcodeFormat.code128,
    this.qrValue,
    this.linkUrl,
    this.linkLabel,
    this.terms,
    this.validUntil,
    this.address,
    this.locality,
    this.lat,
    this.lng,
    this.locked = false,
    this.hasDiscountCode = false,
    this.hasBarcode = false,
    this.hasQr = false,
  });

  final String id;
  final PartnerKind kind;
  final String name;
  final String? brand;

  /// Frase curta do banner ("10% em combustível").
  final String? headline;
  final String? description;
  final String? imagePath;
  final String? discountCode;
  final String? barcodeValue;
  final PartnerBarcodeFormat barcodeFormat;

  /// Texto ou link que vai no QR da promoção.
  final String? qrValue;
  final String? linkUrl;
  final String? linkLabel;
  final String? terms;
  final DateTime? validUntil;
  final String? address;
  final String? locality;
  final double? lat;
  final double? lng;

  /// Só Pro+ e quem vê não é Pro+: os códigos não vêm do servidor.
  final bool locked;
  final bool hasDiscountCode;
  final bool hasBarcode;
  final bool hasQr;

  String? get imageUrl => partnerImageUrl(imagePath);
  bool get hasLocation => lat != null && lng != null;

  /// O que o Pro+ desbloqueia, para o aviso ("código de desconto e QR").
  List<String> get lockedPerks => [
    if (hasDiscountCode) 'código de desconto',
    if (hasBarcode) 'código de barras',
    if (hasQr) 'QR da promoção',
  ];

  factory Partner.fromJson(Map<String, dynamic> json) => Partner(
    id: json['id'] as String,
    kind: PartnerKind.fromValue(json['kind'] as String?),
    name: _text(json['name']) ?? 'Parceiro',
    brand: _text(json['brand']),
    headline: _text(json['headline']),
    description: _text(json['description']),
    imagePath: _text(json['image_path']),
    discountCode: _text(json['discount_code']),
    barcodeValue: _text(json['barcode_value']),
    barcodeFormat: PartnerBarcodeFormat.fromValue(
      json['barcode_format'] as String?,
    ),
    qrValue: _text(json['qr_value']),
    linkUrl: _text(json['link_url']),
    linkLabel: _text(json['link_label']),
    terms: _text(json['terms']),
    validUntil: json['valid_until'] is String
        ? DateTime.tryParse(json['valid_until'] as String)
        : null,
    address: _text(json['address']),
    locality: _text(json['locality']),
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
    locked: json['locked'] == true,
    hasDiscountCode: json['has_discount_code'] == true,
    hasBarcode: json['has_barcode'] == true,
    hasQr: json['has_qr'] == true,
  );
}

/// Partes do ecrã de um parceiro, pela ordem em que aparecem. Só entram as
/// que têm conteúdo (a app nunca mostra uma secção vazia).
enum PartnerSection {
  description,
  locked,
  discountCode,
  barcode,
  qr,
  location,
  link,
  terms,
}

List<PartnerSection> partnerSections(Partner p) => [
  if (p.description != null) PartnerSection.description,
  if (p.locked && p.lockedPerks.isNotEmpty) PartnerSection.locked,
  if (p.discountCode != null) PartnerSection.discountCode,
  if (p.barcodeValue != null) PartnerSection.barcode,
  if (p.qrValue != null) PartnerSection.qr,
  if (p.hasLocation || p.address != null) PartnerSection.location,
  if (p.linkUrl != null) PartnerSection.link,
  if (p.terms != null || p.validUntil != null) PartnerSection.terms,
];
