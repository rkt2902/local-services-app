/// Fase 3 do painel (migration 0081): funil, exportar CSV e avisos a
/// grupos.
library;

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// Um degrau do funil: quantos chegaram e a percentagem do primeiro.
class AdminFunnelStep {
  const AdminFunnelStep({required this.label, required this.count});

  final String label;
  final int count;
}

/// `admin_funnel`: três funis do período.
class AdminFunnel {
  const AdminFunnel({
    required this.clients,
    required this.jobs,
    required this.workers,
    this.jobsOpen = 0,
    this.jobsNoResponse = 0,
    this.jobsCancelled = 0,
    this.medianHoursToFirstProposal,
  });

  final List<AdminFunnelStep> clients;
  final List<AdminFunnelStep> jobs;
  final List<AdminFunnelStep> workers;
  final int jobsOpen;
  final int jobsNoResponse;
  final int jobsCancelled;
  final double? medianHoursToFirstProposal;

  factory AdminFunnel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> part(String k) =>
        ((json[k] as Map?) ?? const {}).cast<String, dynamic>();
    final c = part('clients');
    final j = part('jobs');
    final w = part('workers');
    List<AdminFunnelStep> steps(
      Map<String, dynamic> m,
      List<(String, String)> keys,
    ) => [
      for (final (key, label) in keys)
        AdminFunnelStep(label: label, count: _int(m[key])),
    ];
    return AdminFunnel(
      clients: steps(c, const [
        ('signed_up', 'Registaram-se'),
        ('posted', 'Fizeram um pedido'),
        ('got_proposal', 'Receberam proposta'),
        ('hired', 'Aceitaram uma proposta'),
        ('completed', 'Trabalho concluído'),
        ('rated', 'Avaliaram'),
      ]),
      jobs: steps(j, const [
        ('created', 'Pedidos criados'),
        ('with_proposal', 'Com proposta'),
        ('accepted', 'Proposta aceite'),
        ('completed', 'Concluídos'),
        ('rated', 'Avaliados'),
      ]),
      workers: steps(w, const [
        ('signed_up', 'Registaram-se'),
        ('profile_ready', 'Perfil completo'),
        ('proposed', 'Fizeram proposta'),
        ('hired', 'Foram contratados'),
        ('completed', 'Concluíram um trabalho'),
        ('paid_plan', 'Plano Pro ou Pro+'),
      ]),
      jobsOpen: _int(j['open']),
      jobsNoResponse: _int(j['no_response']),
      jobsCancelled: _int(j['cancelled']),
      medianHoursToFirstProposal: (j['median_hours_to_first_proposal'] as num?)
          ?.toDouble(),
    );
  }
}

/// "45%" do primeiro degrau; "—" sem base.
String adminFunnelPercent(int count, int first) {
  if (first <= 0) return '—';
  return '${(count * 100 / first).round()}%';
}

enum AdminExportKind {
  jobs('jobs', 'Pedidos', 'pedidos'),
  clients('clients', 'Clientes', 'clientes'),
  workers('workers', 'Profissionais', 'profissionais');

  const AdminExportKind(this.value, this.label, this.fileStem);

  final String value;
  final String label;
  final String fileStem;
}

/// `admin_export_rows`: colunas e linhas, para escrever em CSV.
class AdminExportTable {
  const AdminExportTable({required this.columns, required this.rows});

  final List<String> columns;
  final List<List<Object?>> rows;

  factory AdminExportTable.fromJson(Map<String, dynamic> json) =>
      AdminExportTable(
        columns: [for (final c in (json['columns'] as List?) ?? const []) '$c'],
        rows: [
          for (final r in (json['rows'] as List?) ?? const [])
            List<Object?>.from(r as List),
        ],
      );
}

/// CSV para o Excel em português: separador `;` (a vírgula é decimal),
/// BOM UTF-8 para os acentos, aspas quando é preciso.
String adminCsv(AdminExportTable table) {
  String cell(Object? v) {
    if (v == null) return '';
    final text = v is double ? v.toString().replaceAll('.', ',') : v.toString();
    if (text.contains(RegExp('[;"\n\r]'))) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  final buffer = StringBuffer('﻿')..write(table.columns.map(cell).join(';'));
  for (final row in table.rows) {
    buffer
      ..write('\r\n')
      ..write(row.map(cell).join(';'));
  }
  return buffer.toString();
}

/// "projardim-pedidos-2026-11-16.csv".
String adminCsvFileName(AdminExportKind kind, DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'projardim-${kind.fileStem}-${now.year}-${two(now.month)}-'
      '${two(now.day)}.csv';
}

/// Para quem é um aviso. Os filtros de plano e serviço só valem para
/// jardineiros.
class AdminNoticeAudience {
  const AdminNoticeAudience({
    this.role = 'worker',
    this.tiers = const {},
    this.serviceTypeId,
    this.area = '',
  });

  final String role;

  /// `free`, `pro`, `pro_plus`; vazio = todos.
  final Set<String> tiers;
  final String? serviceTypeId;
  final String area;

  bool get isWorkers => role == 'worker';

  AdminNoticeAudience copyWith({
    String? role,
    Set<String>? tiers,
    String? Function()? serviceTypeId,
    String? area,
  }) => AdminNoticeAudience(
    role: role ?? this.role,
    tiers: tiers ?? this.tiers,
    serviceTypeId: serviceTypeId != null ? serviceTypeId() : this.serviceTypeId,
    area: area ?? this.area,
  );

  /// Parâmetros das RPCs (sem os filtros que não se aplicam).
  Map<String, dynamic> toParams() => {
    'p_role': role,
    'p_tiers': isWorkers && tiers.isNotEmpty ? (tiers.toList()..sort()) : null,
    'p_service_type_id': isWorkers ? serviceTypeId : null,
    'p_area': area.trim().isEmpty ? null : area.trim(),
  };

  @override
  bool operator ==(Object other) =>
      other is AdminNoticeAudience &&
      other.role == role &&
      other.serviceTypeId == serviceTypeId &&
      other.area.trim() == area.trim() &&
      other.tiers.length == tiers.length &&
      other.tiers.containsAll(tiers);

  @override
  int get hashCode => Object.hash(
    role,
    serviceTypeId,
    area.trim(),
    Object.hashAllUnordered(tiers),
  );
}

/// Um envio no histórico.
class AdminNoticeRow {
  const AdminNoticeRow({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    required this.recipients,
    required this.readCount,
    required this.createdAt,
    this.adminEmail,
    this.partnerId,
    this.partnerName,
    this.totalCount = 0,
  });

  final String id;
  final String title;
  final String body;
  final Map<String, dynamic> audience;
  final int recipients;
  final int readCount;
  final DateTime? createdAt;
  final String? adminEmail;

  /// Aviso de parceiro (0082): ao tocar, o jardineiro abre este parceiro.
  final String? partnerId;
  final String? partnerName;
  final int totalCount;

  factory AdminNoticeRow.fromJson(Map<String, dynamic> json) => AdminNoticeRow(
    id: json['id'] as String,
    title: (json['title'] as String?) ?? '',
    body: (json['body'] as String?) ?? '',
    audience: ((json['audience'] as Map?) ?? const {}).cast<String, dynamic>(),
    recipients: _int(json['recipients']),
    readCount: _int(json['read_count']),
    createdAt: json['created_at'] is String
        ? DateTime.tryParse(json['created_at'] as String)?.toLocal()
        : null,
    adminEmail: json['admin_email'] as String?,
    partnerId: json['partner_id'] as String?,
    partnerName: json['partner_name'] as String?,
    totalCount: _int(json['total_count']),
  );
}

/// "Profissionais · Pro · Braga" a partir do `audience` gravado.
String adminNoticeAudienceLabel(
  Map<String, dynamic> audience, {
  String? serviceName,
}) {
  const tierNames = {'free': 'Grátis', 'pro': 'Pro', 'pro_plus': 'Pro+'};
  final tiers = [
    for (final t in (audience['tiers'] as List?) ?? const [])
      tierNames[t] ?? '$t',
  ];
  return [
    audience['role'] == 'client' ? 'Clientes' : 'Profissionais',
    if (tiers.isNotEmpty) tiers.join(', '),
    ?serviceName,
    if (audience['area'] is String) audience['area'] as String,
  ].join(' · ');
}
