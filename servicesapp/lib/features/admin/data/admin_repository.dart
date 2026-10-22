import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/enums.dart';
import 'admin_models.dart';

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

/// Painel `/admin` (migration 0059). Todas as RPCs `admin_*` recusam quem
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
    return AdminOverview.fromJson(
      (data as Map).cast<String, dynamic>(),
    );
  }

  Future<List<AdminWorkerRow>> fetchWorkers({
    String? search,
    WorkerPlanTier? tier,
    required int limit,
    required int offset,
  }) async {
    final data = await _client.rpc('admin_list_workers', params: {
      'p_search': (search ?? '').trim().isEmpty ? null : search!.trim(),
      'p_tier': tier?.value,
      'p_limit': limit,
      'p_offset': offset,
    });
    return (data as List)
        .map((e) => AdminWorkerRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AdminWorkerDetail> fetchWorker(String workerId) async {
    final data = await _client
        .rpc('admin_get_worker', params: {'p_worker_id': workerId});
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
    await _client.rpc('admin_set_worker_plan', params: {
      'p_worker_id': workerId,
      'p_tier': tier.value,
      'p_starts_at': day.format(startsAt),
      'p_ends_at': endsAt == null ? null : day.format(endsAt),
      'p_verified_at': verifiedAt == null ? null : day.format(verifiedAt),
      'p_notes': notes,
    });
  }
}
