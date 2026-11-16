/// Fase C do painel de suporte (migration 0080): estado da conta de uma
/// pessoa, ficheiros a apagar depois de eliminar e pontos do mapa.
library;

DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

String? _text(Object? v) =>
    v is String && v.trim().isNotEmpty ? v.trim() : null;

/// `admin_get_account`: o que o cartão "Conta" da ficha mostra.
class AdminAccountState {
  const AdminAccountState({
    required this.id,
    this.role,
    this.deletedAt,
    this.suspendedAt,
    this.suspendedReason,
    this.suspendedMessage,
    this.closingAt,
    this.closingReason,
    this.closingMessage,
    this.avatarUrl,
    this.portfolio = const [],
    this.isAdmin = false,
    this.deletionBlocker,
    this.jobsInProgress = 0,
    this.emailMasked,
    this.emailConfirmed,
    this.lastSignInAt,
  });

  final String id;
  final String? role;
  final DateTime? deletedAt;
  final DateTime? suspendedAt;
  final String? suspendedReason;
  final String? suspendedMessage;
  final DateTime? closingAt;
  final String? closingReason;
  final String? closingMessage;
  final String? avatarUrl;
  final List<String> portfolio;
  final bool isAdmin;

  /// Mensagem de `account_deletion_blocker` (trabalho em curso), ou `null`
  /// quando se pode eliminar.
  final String? deletionBlocker;
  final int jobsInProgress;
  final String? emailMasked;

  /// `null` quando a BD não tem `auth.users` (testes).
  final bool? emailConfirmed;
  final DateTime? lastSignInAt;

  bool get isDeleted => deletedAt != null;
  bool get isSuspended => suspendedAt != null;
  bool get hasClosing => closingAt != null && !isSuspended;

  factory AdminAccountState.fromJson(Map<String, dynamic> json) =>
      AdminAccountState(
        id: json['id'] as String,
        role: json['role'] as String?,
        deletedAt: _date(json['deleted_at']),
        suspendedAt: _date(json['suspended_at']),
        suspendedReason: _text(json['suspended_reason']),
        suspendedMessage: _text(json['suspended_message']),
        closingAt: _date(json['closing_at']),
        closingReason: _text(json['closing_reason']),
        closingMessage: _text(json['closing_message']),
        avatarUrl: _text(json['avatar_url']),
        portfolio: [
          for (final p in (json['portfolio'] as List?) ?? const [])
            if (p is String && p.isNotEmpty) p,
        ],
        isAdmin: json['is_admin'] == true,
        deletionBlocker: _text(json['deletion_blocker']),
        jobsInProgress: (json['jobs_in_progress'] as num?)?.toInt() ?? 0,
        emailMasked: _text(json['email_masked']),
        emailConfirmed: json['email_confirmed'] as bool?,
        lastSignInAt: _date(json['last_sign_in_at']),
      );
}

/// O que `admin_erase_user` devolve: ficheiros no Storage que o SQL não
/// apaga. Apagam-se à mão no painel do Supabase.
class AdminErasedFiles {
  const AdminErasedFiles({
    required this.avatars,
    required this.jobPhotosFolder,
    required this.jobPhotos,
  });

  final List<String> avatars;
  final String? jobPhotosFolder;
  final List<String> jobPhotos;

  factory AdminErasedFiles.fromJson(Map<String, dynamic> json) {
    List<String> list(Object? v) => [
      for (final p in (v as List?) ?? const [])
        if (p is String && p.isNotEmpty) p,
    ];
    return AdminErasedFiles(
      avatars: list(json['avatars']),
      jobPhotosFolder: _text(json['job_photos_folder']),
      jobPhotos: list(json['job_photos']),
    );
  }

  /// Texto para copiar: um caminho por linha, com o bucket à frente.
  String get asText => [
    for (final a in avatars) 'avatars/$a',
    if (jobPhotosFolder != null) 'job-photos/$jobPhotosFolder (pasta toda)',
    for (final p in jobPhotos) 'job-photos/$p',
  ].join('\n');
}

enum AdminMapKind { job, worker }

/// Um ponto de `admin_map_points`: pedido (com estado) ou jardineiro (com
/// raio e plano).
class AdminMapPoint {
  const AdminMapPoint({
    required this.kind,
    required this.id,
    required this.lat,
    required this.lng,
    required this.label,
    required this.status,
    this.radiusKm,
    this.service,
    this.plan,
    this.createdAt,
  });

  final AdminMapKind kind;
  final String id;
  final double lat;
  final double lng;
  final String label;

  /// Pedido: `open`, `confirmed`, `awaiting_confirmation`, `completed`.
  /// Jardineiro: `active` ou `suspended`.
  final String status;
  final int? radiusKm;
  final String? service;
  final String? plan;
  final DateTime? createdAt;

  bool get isJob => kind == AdminMapKind.job;

  factory AdminMapPoint.fromJson(Map<String, dynamic> json) => AdminMapPoint(
    kind: json['kind'] == 'worker' ? AdminMapKind.worker : AdminMapKind.job,
    id: json['id'] as String,
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    label: (json['label'] as String?) ?? '',
    status: (json['status'] as String?) ?? '',
    radiusKm: (json['radius_km'] as num?)?.toInt(),
    service: json['service'] as String?,
    plan: json['plan'] as String?,
    createdAt: _date(json['created_at']),
  );
}

/// Camadas do mapa que se ligam e desligam.
enum AdminMapLayer {
  openJobs('Pedidos abertos'),
  activeJobs('Em curso'),
  doneJobs('Concluídos (30 dias)'),
  workers('Jardineiros'),
  radius('Raio de cada jardineiro');

  const AdminMapLayer(this.label);
  final String label;
}

/// Pontos visíveis com as camadas ligadas. O raio só aparece com os
/// jardineiros ligados.
List<AdminMapPoint> adminVisibleMapPoints(
  List<AdminMapPoint> points,
  Set<AdminMapLayer> layers,
) => [
  for (final p in points)
    if (switch (p.kind) {
      AdminMapKind.worker => layers.contains(AdminMapLayer.workers),
      AdminMapKind.job => switch (p.status) {
        'open' => layers.contains(AdminMapLayer.openJobs),
        'completed' => layers.contains(AdminMapLayer.doneJobs),
        _ => layers.contains(AdminMapLayer.activeJobs),
      },
    })
      p,
];
