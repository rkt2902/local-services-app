/// Cartões frota, parceiros e zonas do mapa (migration 0082).
library;

import '../../../core/theme/app_status_color.dart';
import '../../partners/data/partner_model.dart';

export '../../partners/data/partner_model.dart'
    show PartnerBarcodeFormat, PartnerKind;

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

double? _double(Object? v) => (v as num?)?.toDouble();

DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

String? _text(Object? v) =>
    v is String && v.trim().isNotEmpty ? v.trim() : null;

// ── Cartões frota ──────────────────────────────────────────────────

/// Filtros da lista: (rótulo, estado). `null` = todos.
const adminFleetFilters = <(String, String?)>[
  ('Por aprovar', 'pending'),
  ('Ativos', 'active'),
  ('Recusados', 'rejected'),
  ('Todos', null),
];

/// Uma linha de `admin_list_fleet_cards`.
class AdminFleetCardRow {
  const AdminFleetCardRow({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.status,
    required this.barcodeValue,
    this.locationName,
    this.plan = 'free',
    this.workerSuspended = false,
    this.cardNumber,
    this.holderName,
    this.createdAt,
    this.reviewedAt,
    this.reviewMessage,
    this.attempts = 1,
    this.isLatest = true,
    this.totalCount = 0,
  });

  final String id;
  final String workerId;
  final String workerName;
  final String? locationName;
  final String plan;
  final bool workerSuspended;
  final String? cardNumber;
  final String? holderName;
  final String barcodeValue;

  /// `pending`, `active`, `rejected`.
  final String status;
  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final String? reviewMessage;
  final int attempts;

  /// `false`: o jardineiro já pediu outro depois deste (só histórico).
  final bool isLatest;
  final int totalCount;

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';

  /// O cartão frota é benefício do Pro+.
  bool get planHasBenefit => plan == 'pro_plus';

  factory AdminFleetCardRow.fromJson(Map<String, dynamic> json) =>
      AdminFleetCardRow(
        id: json['id'] as String,
        workerId: json['worker_id'] as String,
        workerName: _text(json['worker_name']) ?? 'Profissional',
        locationName: _text(json['location_name']),
        plan: _text(json['plan']) ?? 'free',
        workerSuspended: json['worker_suspended'] == true,
        cardNumber: _text(json['card_number']),
        holderName: _text(json['holder_name']),
        barcodeValue: (json['barcode_value'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'pending',
        createdAt: _date(json['created_at']),
        reviewedAt: _date(json['reviewed_at']),
        reviewMessage: _text(json['review_message']),
        attempts: _int(json['attempts']),
        isLatest: json['is_latest'] != false,
        totalCount: _int(json['total_count']),
      );
}

/// (rótulo, cor) do estado de um cartão.
(String, AppStatusColor) adminFleetStatus(String status) => switch (status) {
  'active' => ('Ativo', AppStatusColor.success),
  'rejected' => ('Recusado', AppStatusColor.cancelled),
  _ => ('Por aprovar', AppStatusColor.waiting),
};

/// Motivos de recusa (iguais à BD). [message] é o que o jardineiro lê
/// quando o admin não escreve outra coisa.
enum AdminFleetRejectReason {
  unreadable(
    'unreadable',
    'Dados ilegíveis',
    'Não conseguimos ler os dados do cartão. Fotografa-o outra vez, com boa luz.',
  ),
  notEligible(
    'not_eligible',
    'Plano sem o benefício',
    'O cartão frota é um benefício do plano Pro+.',
  ),
  partnerRefused(
    'partner_refused',
    'A gasolineira não aceitou',
    'A gasolineira parceira não aceitou este cartão.',
  ),
  other('other', 'Outro', null);

  const AdminFleetRejectReason(this.value, this.label, this.message);

  final String value;
  final String label;
  final String? message;
}

// ── Parceiros ──────────────────────────────────────────────────────

enum AdminPartnerStatus {
  prospect('prospect', 'Em conversa', AppStatusColor.waiting),
  active('active', 'Parceiro', AppStatusColor.info),
  ended('ended', 'Terminado', AppStatusColor.neutral);

  const AdminPartnerStatus(this.value, this.label, this.tone);

  final String value;
  final String label;
  final AppStatusColor tone;

  static AdminPartnerStatus fromValue(String? v) => values.firstWhere(
    (s) => s.value == v,
    orElse: () => AdminPartnerStatus.prospect,
  );
}

/// Uma linha de `admin_list_partners`: tudo o que o painel edita, mais o
/// que há perto (10 km; pedidos dos últimos 90 dias) quando tem
/// localização.
class AdminPartner {
  const AdminPartner({
    required this.id,
    required this.name,
    required this.status,
    this.kind = PartnerKind.fuelStation,
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
    this.visibleInApp = false,
    this.proPlusOnly = true,
    this.sortOrder = 100,
    this.address,
    this.locality,
    this.lat,
    this.lng,
    this.notes,
    this.createdAt,
    this.workersCovering = 0,
    this.workersNearby = 0,
    this.jobsNearby = 0,
    this.jobsUnanswered = 0,
    this.workersOpened30d = 0,
    this.workersOpenedTotal = 0,
    this.workersCopied30d = 0,
    this.workersLink30d = 0,
    this.workersMap30d = 0,
  });

  final String id;
  final PartnerKind kind;
  final String name;
  final String? brand;
  final AdminPartnerStatus status;
  final String? headline;
  final String? description;
  final String? imagePath;
  final String? discountCode;
  final String? barcodeValue;
  final PartnerBarcodeFormat barcodeFormat;
  final String? qrValue;
  final String? linkUrl;
  final String? linkLabel;
  final String? terms;
  final DateTime? validUntil;

  /// Aparece na tab "Parceiros" da app (se também estiver ativo).
  final bool visibleInApp;

  /// Códigos (desconto, barras, QR) só para quem tem Pro+.
  final bool proPlusOnly;
  final int sortOrder;
  final String? address;
  final String? locality;
  final double? lat;
  final double? lng;
  final String? notes;
  final DateTime? createdAt;

  /// Jardineiros cujo raio chega ao parceiro.
  final int workersCovering;

  /// Jardineiros com base a 10 km ou menos.
  final int workersNearby;
  final int jobsNearby;
  final int jobsUnanswered;

  /// Uso na app (jardineiros diferentes): abriram nos últimos 30 dias e
  /// desde sempre; copiaram o código, abriram o link e o mapa em 30 dias.
  final int workersOpened30d;
  final int workersOpenedTotal;
  final int workersCopied30d;
  final int workersLink30d;
  final int workersMap30d;

  bool get hasLocation => lat != null && lng != null;

  /// Os jardineiros veem-no agora? (ativo, visível e dentro da validade).
  bool shownInApp({DateTime? today}) {
    if (!visibleInApp || status != AdminPartnerStatus.active) return false;
    final until = validUntil;
    if (until == null) return true;
    final now = today ?? DateTime.now();
    return !DateTime(
      until.year,
      until.month,
      until.day,
    ).isBefore(DateTime(now.year, now.month, now.day));
  }

  factory AdminPartner.fromJson(Map<String, dynamic> json) => AdminPartner(
    id: json['id'] as String,
    kind: PartnerKind.fromValue(json['kind'] as String?),
    name: _text(json['name']) ?? 'Parceiro',
    brand: _text(json['brand']),
    status: AdminPartnerStatus.fromValue(json['status'] as String?),
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
    visibleInApp: json['visible_in_app'] == true,
    proPlusOnly: json['pro_plus_only'] != false,
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 100,
    address: _text(json['address']),
    locality: _text(json['locality']),
    lat: _double(json['lat']),
    lng: _double(json['lng']),
    notes: _text(json['notes']),
    createdAt: _date(json['created_at']),
    workersCovering: _int(json['workers_covering']),
    workersNearby: _int(json['workers_nearby']),
    jobsNearby: _int(json['jobs_nearby']),
    jobsUnanswered: _int(json['jobs_unanswered']),
    workersOpened30d: _int(json['workers_opened_30d']),
    workersOpenedTotal: _int(json['workers_opened_total']),
    workersCopied30d: _int(json['workers_copied_30d']),
    workersLink30d: _int(json['workers_link_30d']),
    workersMap30d: _int(json['workers_map_30d']),
  );
}

/// Uso na app nos últimos 30 dias: "12 jardineiros abriram · 4 copiaram o
/// código · 3 abriram o link (40 desde o início)". `null` quando nunca
/// ninguém o abriu e não está na app (nada a dizer).
String? adminPartnerUsageLabel(AdminPartner p) {
  if (p.workersOpenedTotal == 0) {
    return p.shownInApp() ? 'Ainda nenhum profissional o abriu na app' : null;
  }
  String workers(int n) => n == 1 ? '1 profissional' : '$n profissionais';
  final parts = [
    '${workers(p.workersOpened30d)} '
        '${p.workersOpened30d == 1 ? 'abriu' : 'abriram'}',
    if (p.workersCopied30d > 0)
      '${p.workersCopied30d} '
          '${p.workersCopied30d == 1 ? 'copiou' : 'copiaram'} o código',
    if (p.workersLink30d > 0)
      '${p.workersLink30d} ${p.workersLink30d == 1 ? 'abriu' : 'abriram'} o link',
    if (p.workersMap30d > 0)
      '${p.workersMap30d} ${p.workersMap30d == 1 ? 'abriu' : 'abriram'} o mapa',
  ];
  return 'Últimos 30 dias: ${parts.join(' · ')} '
      '(${workers(p.workersOpenedTotal)} desde o início)';
}

/// Alerta da Visão geral (`admin_partner_alerts`).
class AdminPartnerAlerts {
  const AdminPartnerAlerts({this.endingSoon = 0, this.expiredVisible = 0});

  /// Na app e acabam nos próximos 7 dias.
  final int endingSoon;

  /// Marcados "na app" mas já passaram a validade (já não aparecem).
  final int expiredVisible;

  static const none = AdminPartnerAlerts();

  factory AdminPartnerAlerts.fromJson(Map<String, dynamic> json) =>
      AdminPartnerAlerts(
        endingSoon: _int(json['ending_soon']),
        expiredVisible: _int(json['expired_visible']),
      );
}

/// Texto dos alertas da Visão geral, um por linha.
List<String> adminPartnerAlertMessages(AdminPartnerAlerts a) => [
  if (a.endingSoon > 0)
    a.endingSoon == 1
        ? '1 parceiro acaba nos próximos 7 dias'
        : '${a.endingSoon} parceiros acabam nos próximos 7 dias',
  if (a.expiredVisible > 0)
    a.expiredVisible == 1
        ? '1 parceiro passou a validade e já não aparece na app'
        : '${a.expiredVisible} parceiros passaram a validade e já não '
              'aparecem na app',
];

/// Título e texto sugeridos para avisar os jardineiros de um parceiro.
(String, String) adminPartnerNoticeDraft(AdminPartner p) {
  final title = 'Parceiro novo: ${p.name}';
  final body = p.headline != null
      ? '${p.headline}. Vê os detalhes na tab Parceiros.'
      : 'Há um parceiro novo na tab Parceiros. Toca para ver.';
  return (title.length > 80 ? '${title.substring(0, 79)}…' : title, body);
}

/// "2 profissionais cobrem · 5 pedidos a 10 km (1 sem resposta)". Sem
/// localização não há números.
String adminPartnerReachLabel(AdminPartner p) {
  if (!p.hasLocation) return 'Sem localização no mapa';
  final workers = switch (p.workersCovering) {
    0 => 'Nenhum profissional cobre',
    1 => '1 profissional cobre',
    final n => '$n profissionais cobrem',
  };
  final jobs = p.jobsNearby == 1 ? '1 pedido' : '${p.jobsNearby} pedidos';
  return [
    workers,
    '$jobs a 10 km em 90 dias'
        '${p.jobsUnanswered > 0 ? ' (${p.jobsUnanswered} sem resposta)' : ''}',
  ].join(' · ');
}

/// Tem algum código (desconto, barras ou QR)?
bool adminPartnerHasCodes(AdminPartner p) =>
    p.discountCode != null || p.barcodeValue != null || p.qrValue != null;

/// O que está preenchido para a app: "Foto · Código · QR · Link". Ajuda a
/// ver de relance o que o jardineiro vai ter no ecrã do parceiro.
String adminPartnerFilledLabel(AdminPartner p) {
  final parts = [
    if (p.imagePath != null) 'Foto',
    if (p.description != null) 'Descrição',
    if (p.discountCode != null) 'Código',
    if (p.barcodeValue != null) 'Código de barras',
    if (p.qrValue != null) 'QR',
    if (p.linkUrl != null) 'Link',
    if (p.terms != null) 'Condições',
    if (p.validUntil != null)
      'Até ${p.validUntil!.day}/${p.validUntil!.month}/${p.validUntil!.year}',
  ];
  return parts.isEmpty ? 'Só o nome, por agora' : parts.join(' · ');
}

/// EAN-13: 13 dígitos e o último é o dígito de controlo (igual à BD).
bool adminIsValidEan13(String code) {
  if (!RegExp(r'^\d{13}$').hasMatch(code)) return false;
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    final d = code.codeUnitAt(i) - 48;
    sum += i.isEven ? d : d * 3;
  }
  return (10 - sum % 10) % 10 == code.codeUnitAt(12) - 48;
}

/// Code 128: letras sem acentos, números e símbolos simples, até 80.
bool adminIsValidCode128(String code) =>
    code.length <= 80 && RegExp(r'^[ -~]+$').hasMatch(code);

/// Erro do código de barras para o formulário, `null` se está bem.
String? adminBarcodeError(String value, PartnerBarcodeFormat format) {
  final v = value.trim();
  if (v.isEmpty) return null;
  return switch (format) {
    PartnerBarcodeFormat.ean13 when !adminIsValidEan13(v) =>
      '13 dígitos, e o último tem de bater certo.',
    PartnerBarcodeFormat.code128 when !adminIsValidCode128(v) =>
      'Só letras sem acentos, números e símbolos simples.',
    _ => null,
  };
}

/// Erro do link para o formulário, `null` se está bem ou vazio.
String? adminLinkError(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  return RegExp(r'^https://\S+$').hasMatch(v)
      ? null
      : 'Tem de começar por https://';
}

/// O que se grava com `admin_save_partner` (`p_data`). Texto em branco
/// fica `null` na BD e a app não mostra essa parte.
class AdminPartnerDraft {
  const AdminPartnerDraft({
    this.id,
    required this.name,
    required this.status,
    this.kind = PartnerKind.fuelStation,
    this.lat,
    this.lng,
    this.brand = '',
    this.headline = '',
    this.description = '',
    this.imagePath,
    this.discountCode = '',
    this.barcodeValue = '',
    this.barcodeFormat = PartnerBarcodeFormat.code128,
    this.qrValue = '',
    this.linkUrl = '',
    this.linkLabel = '',
    this.terms = '',
    this.validUntil,
    this.visibleInApp = false,
    this.proPlusOnly = true,
    this.sortOrder = 100,
    this.address = '',
    this.locality = '',
    this.notes = '',
  });

  factory AdminPartnerDraft.from(AdminPartner p) => AdminPartnerDraft(
    id: p.id,
    name: p.name,
    status: p.status,
    kind: p.kind,
    lat: p.lat,
    lng: p.lng,
    brand: p.brand ?? '',
    headline: p.headline ?? '',
    description: p.description ?? '',
    imagePath: p.imagePath,
    discountCode: p.discountCode ?? '',
    barcodeValue: p.barcodeValue ?? '',
    barcodeFormat: p.barcodeFormat,
    qrValue: p.qrValue ?? '',
    linkUrl: p.linkUrl ?? '',
    linkLabel: p.linkLabel ?? '',
    terms: p.terms ?? '',
    validUntil: p.validUntil,
    visibleInApp: p.visibleInApp,
    proPlusOnly: p.proPlusOnly,
    sortOrder: p.sortOrder,
    address: p.address ?? '',
    locality: p.locality ?? '',
    notes: p.notes ?? '',
  );

  final String? id;
  final String name;
  final AdminPartnerStatus status;
  final PartnerKind kind;
  final double? lat;
  final double? lng;
  final String brand;
  final String headline;
  final String description;
  final String? imagePath;
  final String discountCode;
  final String barcodeValue;
  final PartnerBarcodeFormat barcodeFormat;
  final String qrValue;
  final String linkUrl;
  final String linkLabel;
  final String terms;
  final DateTime? validUntil;
  final bool visibleInApp;
  final bool proPlusOnly;
  final int sortOrder;
  final String address;
  final String locality;
  final String notes;

  AdminPartnerDraft withImage(String? path) => AdminPartnerDraft(
    id: id,
    name: name,
    status: status,
    kind: kind,
    lat: lat,
    lng: lng,
    brand: brand,
    headline: headline,
    description: description,
    imagePath: path,
    discountCode: discountCode,
    barcodeValue: barcodeValue,
    barcodeFormat: barcodeFormat,
    qrValue: qrValue,
    linkUrl: linkUrl,
    linkLabel: linkLabel,
    terms: terms,
    validUntil: validUntil,
    visibleInApp: visibleInApp,
    proPlusOnly: proPlusOnly,
    sortOrder: sortOrder,
    address: address,
    locality: locality,
    notes: notes,
  );

  /// Como um jardineiro Pro+ o veria na app (pré-visualização do editor).
  Partner toPreview() {
    String? blank(String v) => v.trim().isEmpty ? null : v.trim();
    return Partner(
      id: id ?? 'preview',
      kind: kind,
      name: name.trim(),
      brand: blank(brand),
      headline: blank(headline),
      description: blank(description),
      imagePath: imagePath,
      discountCode: blank(discountCode),
      barcodeValue: blank(barcodeValue),
      barcodeFormat: barcodeFormat,
      qrValue: blank(qrValue),
      linkUrl: blank(linkUrl),
      linkLabel: blank(linkLabel),
      terms: blank(terms),
      validUntil: validUntil,
      address: blank(address),
      locality: blank(locality),
      lat: lat,
      lng: lng,
    );
  }

  /// `p_data` de `admin_save_partner`, pelos nomes das colunas.
  Map<String, dynamic> toData() {
    String? blank(String v) => v.trim().isEmpty ? null : v.trim();
    final until = validUntil;
    return {
      'name': name.trim(),
      'kind': kind.value,
      'status': status.value,
      'brand': blank(brand),
      'headline': blank(headline),
      'description': blank(description),
      'image_path': imagePath,
      'discount_code': blank(discountCode),
      'barcode_value': blank(barcodeValue),
      'barcode_format': barcodeFormat.value,
      'qr_value': blank(qrValue),
      'link_url': blank(linkUrl),
      'link_label': blank(linkLabel),
      'terms': blank(terms),
      'valid_until': until == null
          ? null
          : '${until.year.toString().padLeft(4, '0')}-'
                '${until.month.toString().padLeft(2, '0')}-'
                '${until.day.toString().padLeft(2, '0')}',
      'visible_in_app': visibleInApp,
      'pro_plus_only': proPlusOnly,
      'sort_order': sortOrder,
      'address': blank(address),
      'locality': blank(locality),
      'lat': lat,
      'lng': lng,
      'notes': blank(notes),
    };
  }
}

/// Portugal continental, Açores e Madeira (igual à BD).
bool adminInPortugal(double lat, double lng) =>
    lat >= 30 && lat <= 42.2 && lng >= -31.5 && lng <= -6.1;

// ── Zonas ──────────────────────────────────────────────────────────

/// Período e tamanho dos quadrados das zonas no mapa.
const adminZoneDays = 90;
const adminZoneCellKm = 10;

/// Um quadrado de `admin_map_zones`.
class AdminMapZone {
  const AdminMapZone({
    required this.cell,
    required this.latMin,
    required this.lngMin,
    required this.latMax,
    required this.lngMax,
    this.area,
    this.jobs = 0,
    this.jobsUnanswered = 0,
    this.jobsCompleted = 0,
    this.medianHoursFirstProposal,
    this.workersBased = 0,
    this.workersCovering = 0,
    this.partners = 0,
  });

  final String cell;
  final double latMin;
  final double lngMin;
  final double latMax;
  final double lngMax;
  final String? area;
  final int jobs;
  final int jobsUnanswered;
  final int jobsCompleted;
  final double? medianHoursFirstProposal;
  final int workersBased;
  final int workersCovering;
  final int partners;

  double get centerLat => (latMin + latMax) / 2;
  double get centerLng => (lngMin + lngMax) / 2;

  /// Parte dos pedidos sem resposta (0 a 1).
  double get unansweredRate => jobs <= 0 ? 0 : jobsUnanswered / jobs;

  /// Conta para "Densidade": há procura (pedidos) ou um parceiro.
  bool get hasDemand => jobs > 0 || partners > 0;

  factory AdminMapZone.fromJson(Map<String, dynamic> json) => AdminMapZone(
    cell: (json['cell'] as String?) ?? '',
    latMin: (json['lat_min'] as num).toDouble(),
    lngMin: (json['lng_min'] as num).toDouble(),
    latMax: (json['lat_max'] as num).toDouble(),
    lngMax: (json['lng_max'] as num).toDouble(),
    area: _text(json['area']),
    jobs: _int(json['jobs']),
    jobsUnanswered: _int(json['jobs_unanswered']),
    jobsCompleted: _int(json['jobs_completed']),
    medianHoursFirstProposal: _double(json['median_hours_first_proposal']),
    workersBased: _int(json['workers_based']),
    workersCovering: _int(json['workers_covering']),
    partners: _int(json['partners']),
  );
}

/// Cor da densidade: ninguém cobre (vermelho), 1 ou 2 (âmbar), 3 ou mais
/// (verde).
AppStatusColor adminZoneCoverageTone(AdminMapZone z) =>
    switch (z.workersCovering) {
      0 => AppStatusColor.cancelled,
      1 || 2 => AppStatusColor.waiting,
      _ => AppStatusColor.success,
    };

/// "3 zonas com pedidos sem resposta · 2 com procura e ninguém a cobrir".
String adminZonesSummary(List<AdminMapZone> zones) {
  final unanswered = zones.where((z) => z.jobsUnanswered > 0).length;
  final uncovered = zones
      .where((z) => z.hasDemand && z.workersCovering == 0)
      .length;
  return [
    '$unanswered ${unanswered == 1 ? 'zona' : 'zonas'} com pedidos sem resposta',
    '$uncovered com procura e ninguém a cobrir',
    'quadrados de $adminZoneCellKm km, $adminZoneDays dias',
  ].join(' · ');
}

/// Zonas a reforçar primeiro: mais pedidos sem resposta, depois procura
/// sem ninguém a cobrir, depois menos jardineiros por pedido.
List<AdminMapZone> adminZonesToReinforce(
  List<AdminMapZone> zones, {
  int limit = 5,
}) {
  double score(AdminMapZone z) =>
      z.jobsUnanswered * 3 +
      (z.workersCovering == 0 ? z.jobs * 2 + z.partners * 2 : 0) +
      (z.jobs / (z.workersCovering + 1));
  final list = [
    for (final z in zones)
      if (z.hasDemand && (z.jobsUnanswered > 0 || z.workersCovering < 3)) z,
  ]..sort((a, b) => score(b).compareTo(score(a)));
  return list.take(limit).toList();
}
