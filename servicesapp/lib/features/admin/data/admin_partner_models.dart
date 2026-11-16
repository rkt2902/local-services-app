/// Cartões frota, gasolineiras parceiras e zonas do mapa (migration 0082).
library;

import '../../../core/theme/app_status_color.dart';

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
        workerName: _text(json['worker_name']) ?? 'Jardineiro',
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

// ── Gasolineiras parceiras ─────────────────────────────────────────

enum AdminPartnerStatus {
  prospect('prospect', 'Em conversa', AppStatusColor.waiting),
  active('active', 'Parceira', AppStatusColor.info),
  ended('ended', 'Terminada', AppStatusColor.neutral);

  const AdminPartnerStatus(this.value, this.label, this.tone);

  final String value;
  final String label;
  final AppStatusColor tone;

  static AdminPartnerStatus fromValue(String? v) => values.firstWhere(
    (s) => s.value == v,
    orElse: () => AdminPartnerStatus.prospect,
  );
}

/// Uma linha de `admin_list_partner_locations`, com o que há perto
/// (10 km; pedidos dos últimos 90 dias).
class AdminPartnerLocation {
  const AdminPartnerLocation({
    required this.id,
    required this.name,
    required this.status,
    required this.lat,
    required this.lng,
    this.kind = 'fuel_station',
    this.brand,
    this.address,
    this.locality,
    this.notes,
    this.createdAt,
    this.workersCovering = 0,
    this.workersNearby = 0,
    this.jobsNearby = 0,
    this.jobsUnanswered = 0,
  });

  final String id;
  final String kind;
  final String name;
  final String? brand;
  final AdminPartnerStatus status;
  final String? address;
  final String? locality;
  final double lat;
  final double lng;
  final String? notes;
  final DateTime? createdAt;

  /// Jardineiros cujo raio chega à gasolineira.
  final int workersCovering;

  /// Jardineiros com base a 10 km ou menos.
  final int workersNearby;
  final int jobsNearby;
  final int jobsUnanswered;

  factory AdminPartnerLocation.fromJson(Map<String, dynamic> json) =>
      AdminPartnerLocation(
        id: json['id'] as String,
        kind: _text(json['kind']) ?? 'fuel_station',
        name: _text(json['name']) ?? 'Gasolineira',
        brand: _text(json['brand']),
        status: AdminPartnerStatus.fromValue(json['status'] as String?),
        address: _text(json['address']),
        locality: _text(json['locality']),
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        notes: _text(json['notes']),
        createdAt: _date(json['created_at']),
        workersCovering: _int(json['workers_covering']),
        workersNearby: _int(json['workers_nearby']),
        jobsNearby: _int(json['jobs_nearby']),
        jobsUnanswered: _int(json['jobs_unanswered']),
      );
}

/// "2 jardineiros cobrem · 5 pedidos a 10 km (1 sem resposta)".
String adminPartnerReachLabel(AdminPartnerLocation p) {
  final workers = switch (p.workersCovering) {
    0 => 'Nenhum jardineiro cobre',
    1 => '1 jardineiro cobre',
    final n => '$n jardineiros cobrem',
  };
  final jobs = p.jobsNearby == 1 ? '1 pedido' : '${p.jobsNearby} pedidos';
  return [
    workers,
    '$jobs a 10 km em 90 dias'
        '${p.jobsUnanswered > 0 ? ' (${p.jobsUnanswered} sem resposta)' : ''}',
  ].join(' · ');
}

/// O que se grava com `admin_save_partner_location`.
class AdminPartnerDraft {
  const AdminPartnerDraft({
    this.id,
    required this.name,
    required this.status,
    required this.lat,
    required this.lng,
    this.brand = '',
    this.address = '',
    this.locality = '',
    this.notes = '',
    this.kind = 'fuel_station',
  });

  factory AdminPartnerDraft.from(AdminPartnerLocation p) => AdminPartnerDraft(
    id: p.id,
    name: p.name,
    status: p.status,
    lat: p.lat,
    lng: p.lng,
    brand: p.brand ?? '',
    address: p.address ?? '',
    locality: p.locality ?? '',
    notes: p.notes ?? '',
    kind: p.kind,
  );

  final String? id;
  final String name;
  final AdminPartnerStatus status;
  final double lat;
  final double lng;
  final String brand;
  final String address;
  final String locality;
  final String notes;
  final String kind;

  Map<String, dynamic> toParams() {
    String? blank(String v) => v.trim().isEmpty ? null : v.trim();
    return {
      'p_id': id,
      'p_name': name.trim(),
      'p_brand': blank(brand),
      'p_kind': kind,
      'p_status': status.value,
      'p_address': blank(address),
      'p_locality': blank(locality),
      'p_lat': lat,
      'p_lng': lng,
      'p_notes': blank(notes),
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

  /// Conta para "Densidade": há procura (pedidos) ou uma gasolineira.
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
