import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/enums.dart';
import 'admin_models.dart';
import 'admin_support_models.dart';

/// Inscrição nova de uma app autenticadora: o [uri] vai para o QR.
class AdminTotpEnrollment {
  const AdminTotpEnrollment({
    required this.factorId,
    required this.uri,
    required this.secret,
  });

  final String factorId;
  final String uri;
  final String secret;
}

/// Painel `/admin` (migration 0060). Todas as RPCs `admin_*` recusam quem
/// não está em `admin_users` ou não tem o segundo fator nesta sessão: a
/// segurança está na BD, a app só mostra o que elas devolvem.
class AdminRepository {
  const AdminRepository(this._client);

  final SupabaseClient _client;

  Future<void> signIn({required String email, required String password}) =>
      _client.auth.signInWithPassword(email: email.trim(), password: password);

  Future<void> signOut() => _client.auth.signOut();

  Future<AdminAccess> fetchAccess() async {
    final rows = await _client.rpc('admin_whoami') as List;
    if (rows.isEmpty) return const AdminAccess(isAdmin: false, hasMfa: false);
    final row = rows.first as Map<String, dynamic>;
    return AdminAccess(
      isAdmin: row['is_admin'] as bool? ?? false,
      hasMfa: row['has_mfa'] as bool? ?? false,
    );
  }

  /// Fator TOTP já confirmado nesta conta, ou `null` (falta inscrever).
  Future<String?> verifiedTotpFactorId() async {
    final factors = await _client.auth.mfa.listFactors();
    return factors.totp.firstOrNull?.id;
  }

  /// Começa a inscrição da app autenticadora. Apaga primeiro inscrições
  /// antigas por confirmar (o Supabase recusa duas com o mesmo nome).
  Future<AdminTotpEnrollment> enrollTotp() async {
    final factors = await _client.auth.mfa.listFactors();
    for (final factor in factors.all) {
      if (factor.status == FactorStatus.unverified) {
        await _client.auth.mfa.unenroll(factor.id);
      }
    }
    final response = await _client.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'ProJardim',
      friendlyName: 'Painel ProJardim',
    );
    final totp = response.totp!;
    return AdminTotpEnrollment(
      factorId: response.id,
      uri: totp.uri,
      secret: totp.secret,
    );
  }

  /// Confirma o código de 6 dígitos. Depois disto a sessão passa a aal2.
  Future<void> verifyTotp({required String factorId, required String code}) =>
      _client.auth.mfa.challengeAndVerify(factorId: factorId, code: code);

  Future<AdminOverview> fetchOverview({int? days}) async {
    final data = await _client.rpc('admin_overview', params: {'p_days': days});
    return AdminOverview.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<List<AdminWorkerRow>> fetchWorkers({
    String? search,
    WorkerPlanTier? tier,
    required int limit,
    required int offset,
  }) async {
    final data = await _client.rpc(
      'admin_list_workers',
      params: {
        'p_search': (search ?? '').trim().isEmpty ? null : search!.trim(),
        'p_tier': tier?.value,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return (data as List)
        .map((e) => AdminWorkerRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AdminWorkerDetail> fetchWorker(String workerId) async {
    final data = await _client.rpc(
      'admin_get_worker',
      params: {'p_worker_id': workerId},
    );
    return AdminWorkerDetail.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<void> setWorkerPlan({
    required String workerId,
    required WorkerPlanTier tier,
    required DateTime startsAt,
    DateTime? endsAt,
    DateTime? verifiedAt,
    String? notes,
  }) async {
    final day = DateFormat('yyyy-MM-dd');
    await _client.rpc(
      'admin_set_worker_plan',
      params: {
        'p_worker_id': workerId,
        'p_tier': tier.value,
        'p_starts_at': day.format(startsAt),
        'p_ends_at': endsAt == null ? null : day.format(endsAt),
        'p_verified_at': verifiedAt == null ? null : day.format(verifiedAt),
        'p_notes': notes,
      },
    );
  }

  // ── Suporte, fase A (migration 0078) ───────────────────────────
  // As consultas a fichas, fotos e contactos ficam registadas em
  // admin_actions pela própria RPC.

  Future<List<AdminSearchHit>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final data = await _client.rpc('admin_search', params: {'p_q': q});
    return (data as List)
        .map((e) => AdminSearchHit.fromJson((e as Map).cast<String, dynamic>()))
        .whereType<AdminSearchHit>()
        .toList();
  }

  Future<List<AdminJobRow>> fetchJobs(
    AdminJobsFilter filter, {
    required int limit,
  }) async {
    final day = DateFormat('yyyy-MM-dd');
    final from = filter.lastDays == null
        ? null
        : DateTime.now().subtract(Duration(days: filter.lastDays!));
    final data = await _client.rpc(
      'admin_list_jobs',
      params: {
        'p_status': filter.status?.value,
        'p_service_id': filter.serviceTypeId,
        'p_area': filter.area.trim().isEmpty ? null : filter.area.trim(),
        'p_from': from == null ? null : day.format(from),
        'p_to': null,
        'p_with_report': filter.withReport ? true : null,
        'p_direct': filter.directOnly ? true : null,
        'p_with_helpers': filter.withHelpers ? true : null,
        'p_limit': limit,
        'p_offset': filter.page * limit,
      },
    );
    return (data as List)
        .map((e) => AdminJobRow.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<AdminJobDetail> fetchJob(String jobId) async {
    final data = await _client.rpc(
      'admin_get_job',
      params: {'p_job_id': jobId},
    );
    return AdminJobDetail.fromJson((data as Map).cast<String, dynamic>());
  }

  /// Os buckets são públicos (AUD-14): basta o caminho para o URL.
  Future<List<AdminJobPhoto>> fetchJobPhotos(String jobId) async {
    final data = await _client.rpc(
      'admin_get_job_photos',
      params: {'p_job_id': jobId},
    );
    final bucket = _client.storage.from('job-photos');
    return (data as List).map((e) {
      final row = (e as Map).cast<String, dynamic>();
      final created = row['created_at'];
      return AdminJobPhoto(
        kind: (row['kind'] as String?) ?? 'request',
        url: bucket.getPublicUrl(row['storage_path'] as String),
        takenBy: (row['taken_by'] as String?) ?? '',
        createdAt: created is String ? DateTime.tryParse(created) : null,
      );
    }).toList();
  }

  Future<List<AdminClientRow>> fetchClients(
    AdminClientsFilter filter, {
    required int limit,
  }) async {
    final data = await _client.rpc(
      'admin_list_clients',
      params: {
        'p_search': filter.search.trim().isEmpty ? null : filter.search.trim(),
        'p_state': filter.state,
        'p_with_reports': filter.withReports ? true : null,
        'p_limit': limit,
        'p_offset': filter.page * limit,
      },
    );
    return (data as List)
        .map((e) => AdminClientRow.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<AdminClientDetail> fetchClient(String clientId) async {
    final data = await _client.rpc(
      'admin_get_client',
      params: {'p_client_id': clientId},
    );
    return AdminClientDetail.fromJson((data as Map).cast<String, dynamic>());
  }

  /// Telefone inteiro de uma pessoa. Fica registado (com o motivo, se vier).
  Future<String?> revealPhone(String personId, {String? reason}) async {
    final data = await _client.rpc(
      'admin_reveal_contact',
      params: {'p_target_id': personId, 'p_kind': 'phone', 'p_reason': reason},
    );
    final phone = (data as Map?)?['phone'] as String?;
    return phone == null || phone.trim().isEmpty ? null : phone;
  }

  /// Morada exata de um pedido. Fica registado.
  Future<AdminRevealedAddress> revealAddress(
    String jobId, {
    String? reason,
  }) async {
    final data = await _client.rpc(
      'admin_reveal_contact',
      params: {'p_target_id': jobId, 'p_kind': 'address', 'p_reason': reason},
    );
    return AdminRevealedAddress.fromJson((data as Map).cast<String, dynamic>());
  }
}
