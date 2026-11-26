import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/enums.dart';
import 'admin_account_models.dart';
import 'admin_growth_models.dart';
import 'admin_partner_stats_models.dart';
import 'admin_models.dart';
import 'admin_partner_models.dart';
import 'admin_resolve_models.dart';
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
        storagePath: row['storage_path'] as String,
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

  // ── Suporte, fase B (migration 0079) ───────────────────────────
  // Cada ação pede motivo da lista e nota, fica em admin_actions e avisa
  // as pessoas (tudo dentro da RPC).

  Future<List<AdminCaseRow>> fetchCases(
    AdminCasesFilter filter, {
    String? targetId,
    required int limit,
  }) async {
    final data = await _client.rpc(
      'admin_list_cases',
      params: {
        'p_status': filter.status,
        'p_kind': filter.kind?.value,
        'p_target_id': targetId,
        'p_limit': limit,
        'p_offset': filter.page * limit,
      },
    );
    return (data as List)
        .map((e) => AdminCaseRow.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<AdminCaseDetail> fetchCase(String caseId) async {
    final data = await _client.rpc(
      'admin_get_case',
      params: {'p_case_id': caseId},
    );
    return AdminCaseDetail.fromJson((data as Map).cast<String, dynamic>());
  }

  /// Devolve o id do caso novo.
  Future<String> createCase({
    required AdminCaseKind kind,
    required String summary,
    String? personId,
    String? jobId,
    String? reportId,
    String? contactEmail,
  }) async {
    final data = await _client.rpc(
      'admin_case_create',
      params: {
        'p_kind': kind.value,
        'p_summary': summary.trim(),
        'p_person_id': personId,
        'p_job_id': jobId,
        'p_report_id': reportId,
        'p_contact_email': (contactEmail ?? '').trim().isEmpty
            ? null
            : contactEmail!.trim(),
      },
    );
    return data as String;
  }

  Future<void> updateCase(
    String caseId, {
    AdminCaseStatus? status,
    String? decision,
  }) => _client.rpc(
    'admin_case_update',
    params: {
      'p_case_id': caseId,
      'p_status': status?.value,
      'p_decision': decision,
    },
  );

  Future<void> addCaseNote(
    String caseId, {
    required String body,
    required bool isReply,
  }) => _client.rpc(
    'admin_case_add_note',
    params: {
      'p_case_id': caseId,
      'p_body': body.trim(),
      'p_kind': isReply ? 'reply' : 'internal',
    },
  );

  /// `status` `null` = novos e em análise; `'all'` = todos.
  Future<List<AdminReportRow>> fetchReports({
    String? status,
    required int limit,
    required int offset,
  }) async {
    final data = await _client.rpc(
      'admin_list_reports',
      params: {'p_status': status, 'p_limit': limit, 'p_offset': offset},
    );
    return (data as List)
        .map((e) => AdminReportRow.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> setReportStatus(
    String reportId, {
    required String status,
    String? note,
  }) => _client.rpc(
    'admin_set_report_status',
    params: {'p_report_id': reportId, 'p_status': status, 'p_note': note},
  );

  Future<void> cancelJob(
    String jobId, {
    required AdminActionReason reason,
    required String note,
    String? publicMessage,
  }) => _client.rpc(
    'admin_cancel_job',
    params: {
      'p_job_id': jobId,
      'p_reason': reason.value,
      'p_note': note.trim(),
      'p_public_message': (publicMessage ?? '').trim().isEmpty
          ? null
          : publicMessage!.trim(),
    },
  );

  Future<void> reopenJob(
    String jobId, {
    required AdminActionReason reason,
    required String note,
  }) => _client.rpc(
    'admin_reopen_job',
    params: {
      'p_job_id': jobId,
      'p_reason': reason.value,
      'p_note': note.trim(),
    },
  );

  /// `completed` ou `awaiting_confirmation` (anular a confirmação).
  Future<void> setJobStatus(
    String jobId, {
    required String status,
    required AdminActionReason reason,
    required String note,
  }) => _client.rpc(
    'admin_set_job_status',
    params: {
      'p_job_id': jobId,
      'p_status': status,
      'p_reason': reason.value,
      'p_note': note.trim(),
    },
  );

  Future<List<AdminModerationRating>> fetchRatings(
    AdminRatingsQuery query, {
    required int limit,
  }) async {
    final data = await _client.rpc(
      'admin_list_ratings',
      params: {
        'p_stars': query.stars,
        'p_hidden': query.hidden,
        'p_with_comment': query.onlyWithComment ? true : null,
        'p_limit': limit,
        'p_offset': query.page * limit,
      },
    );
    return (data as List)
        .map(
          (e) => AdminModerationRating.fromJson(
            (e as Map).cast<String, dynamic>(),
          ),
        )
        .toList();
  }

  Future<void> hideRating(
    String ratingId, {
    required AdminActionReason reason,
    required String note,
  }) => _client.rpc(
    'admin_hide_rating',
    params: {
      'p_rating_id': ratingId,
      'p_reason': reason.value,
      'p_note': note.trim(),
    },
  );

  Future<void> restoreRating(String ratingId, {required String note}) =>
      _client.rpc(
        'admin_restore_rating',
        params: {'p_rating_id': ratingId, 'p_note': note.trim()},
      );

  Future<void> hidePhoto(
    String jobId, {
    required String storagePath,
    required AdminActionReason reason,
    required String note,
  }) => _client.rpc(
    'admin_hide_photo',
    params: {
      'p_job_id': jobId,
      'p_storage_path': storagePath,
      'p_reason': reason.value,
      'p_note': note.trim(),
    },
  );

  Future<List<AdminNote>> fetchNotes(String targetId) async {
    final data = await _client.rpc(
      'admin_list_notes',
      params: {'p_target_id': targetId},
    );
    return (data as List)
        .map((e) => AdminNote.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> addNote(String targetId, String body) => _client.rpc(
    'admin_add_note',
    params: {'p_target_id': targetId, 'p_body': body.trim()},
  );

  Future<List<AdminActionRow>> fetchActions(
    AdminActionsQuery query, {
    String? targetId,
    required int limit,
  }) async {
    final data = await _client.rpc(
      'admin_list_actions',
      params: {
        'p_action': query.action,
        'p_target_id': targetId,
        'p_include_reads': query.includeReads,
        'p_limit': limit,
        'p_offset': query.page * limit,
      },
    );
    return (data as List)
        .map((e) => AdminActionRow.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  // ── Fase C: contas (0080) ──────────────────────────────────────

  Future<AdminAccountState> fetchAccount(String personId) async {
    final data = await _client.rpc(
      'admin_get_account',
      params: {'p_target_id': personId},
    );
    return AdminAccountState.fromJson((data as Map).cast<String, dynamic>());
  }

  /// Devolve quantos trabalhos já aceites ficaram por decidir.
  Future<int> suspendUser(
    String personId, {
    required AdminActionReason reason,
    required String note,
    String? publicMessage,
  }) async {
    final data = await _client.rpc(
      'admin_suspend_user',
      params: {
        'p_target_id': personId,
        'p_reason': reason.value,
        'p_note': note.trim(),
        'p_public_message': _orNull(publicMessage),
      },
    );
    return (data as num?)?.toInt() ?? 0;
  }

  Future<void> reactivateUser(String personId, {required String note}) =>
      _client.rpc(
        'admin_reactivate_user',
        params: {'p_target_id': personId, 'p_note': note.trim()},
      );

  /// Devolve a data em que a conta fica suspensa.
  Future<DateTime?> scheduleClosure(
    String personId, {
    required AdminActionReason reason,
    required String note,
    String? publicMessage,
  }) async {
    final data = await _client.rpc(
      'admin_schedule_closure',
      params: {
        'p_target_id': personId,
        'p_reason': reason.value,
        'p_note': note.trim(),
        'p_public_message': _orNull(publicMessage),
      },
    );
    return data is String ? DateTime.tryParse(data)?.toLocal() : null;
  }

  Future<void> cancelClosure(String personId, {required String note}) =>
      _client.rpc(
        'admin_cancel_closure',
        params: {'p_target_id': personId, 'p_note': note.trim()},
      );

  /// JSON com tudo o que se guarda da pessoa (RGPD). Fica registado.
  Future<Map<String, dynamic>> exportUserData(String personId) async {
    final data = await _client.rpc(
      'admin_export_user_data',
      params: {'p_target_id': personId},
    );
    return (data as Map).cast<String, dynamic>();
  }

  Future<AdminErasedFiles> eraseUser(
    String personId, {
    required String note,
  }) async {
    final data = await _client.rpc(
      'admin_erase_user',
      params: {'p_target_id': personId, 'p_note': note.trim()},
    );
    return AdminErasedFiles.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<void> hideProfilePhoto(
    String personId, {
    required String url,
    required AdminActionReason reason,
    required String note,
  }) => _client.rpc(
    'admin_hide_profile_photo',
    params: {
      'p_target_id': personId,
      'p_url': url,
      'p_reason': reason.value,
      'p_note': note.trim(),
    },
  );

  /// A RPC regista e devolve o email; o envio é o mesmo do ecrã "Confirma
  /// o teu email" da app.
  Future<void> resendConfirmationCode(String personId) async {
    final email = await _client.rpc(
      'admin_resend_code',
      params: {'p_target_id': personId},
    );
    await _client.auth.resend(type: OtpType.signup, email: email as String);
  }

  Future<List<AdminMapPoint>> fetchMapPoints({int days = 30}) async {
    final data = await _client.rpc(
      'admin_map_points',
      params: {'p_days': days},
    );
    return (data as List)
        .map((e) => AdminMapPoint.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  static String? _orNull(String? text) =>
      (text ?? '').trim().isEmpty ? null : text!.trim();

  // ── Estatísticas para parceiros (0084) ────────────────────────

  Future<AdminPartnerStats> fetchPartnerStats({int months = 6}) async {
    final data = await _client.rpc(
      'admin_partner_stats',
      params: {'p_months': months},
    );
    return AdminPartnerStats.fromJson((data as Map).cast<String, dynamic>());
  }

  // ── Fase 3: funil, CSV, avisos (0081) ──────────────────────────

  /// [days] `null` = desde sempre.
  Future<AdminFunnel> fetchFunnel({int? days}) async {
    final data = await _client.rpc(
      'admin_funnel',
      params: {'p_days': days ?? 0},
    );
    return AdminFunnel.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<AdminExportTable> exportRows(AdminExportKind kind, {int? days}) async {
    final data = await _client.rpc(
      'admin_export_rows',
      params: {'p_kind': kind.value, 'p_days': days ?? 0},
    );
    return AdminExportTable.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<int> noticeAudience(AdminNoticeAudience audience) async {
    final data = await _client.rpc(
      'admin_notice_audience',
      params: audience.toParams(),
    );
    return (data as num).toInt();
  }

  /// [expected] é o número que o admin viu; a BD recusa se mudou.
  Future<int> sendNotice({
    required String title,
    required String body,
    required AdminNoticeAudience audience,
    required int expected,
    String? partnerId,
  }) async {
    final data = await _client.rpc(
      'admin_send_notice',
      params: {
        'p_title': title.trim(),
        'p_body': body.trim(),
        ...audience.toParams(),
        'p_expected': expected,
        // Só com parceiro: sem a 0082 a chamada antiga continua a servir.
        'p_partner_id': ?partnerId,
      },
    );
    return (data as num).toInt();
  }

  Future<List<AdminNoticeRow>> fetchNotices({int page = 0}) async {
    final data = await _client.rpc(
      'admin_list_notices',
      params: {'p_limit': 30, 'p_offset': page * 30},
    );
    return (data as List)
        .map((e) => AdminNoticeRow.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  // ── Parceiros e zonas (0082) ──────────────────────────────────────

  /// [status] `null` = todos. Ver a lista fica no Registo.
  Future<List<AdminFleetCardRow>> fetchFleetCards({
    String? status = 'pending',
    int page = 0,
  }) async {
    final data = await _client.rpc(
      'admin_list_fleet_cards',
      params: {'p_status': status, 'p_limit': 50, 'p_offset': page * 50},
    );
    return (data as List)
        .map(
          (e) => AdminFleetCardRow.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  Future<void> approveFleetCard(String cardId) => _client.rpc(
    'admin_review_fleet_card',
    params: {'p_card_id': cardId, 'p_decision': 'active'},
  );

  /// Recusar (por aprovar) ou retirar (ativo). Sem [message], o
  /// jardineiro lê a mensagem do motivo.
  Future<void> rejectFleetCard(
    String cardId, {
    required AdminFleetRejectReason reason,
    String? message,
  }) => _client.rpc(
    'admin_review_fleet_card',
    params: {
      'p_card_id': cardId,
      'p_decision': 'rejected',
      'p_reason': reason.value,
      'p_message': _orNull(message),
    },
  );

  Future<List<AdminPartner>> fetchPartners() async {
    final data = await _client.rpc('admin_list_partners');
    return (data as List)
        .map((e) => AdminPartner.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Cria ou altera; devolve o id.
  Future<String> savePartner(AdminPartnerDraft draft) async {
    final data = await _client.rpc(
      'admin_save_partner',
      params: {'p_id': draft.id, 'p_data': draft.toData()},
    );
    return data as String;
  }

  /// Apaga o parceiro e depois a foto (se havia).
  Future<void> deletePartner(String id) async {
    final image = await _client.rpc(
      'admin_delete_partner',
      params: {'p_id': id},
    );
    if (image is String && image.isNotEmpty) {
      await removePartnerImage(image);
    }
  }

  /// Alerta da Visão geral. Sem a 0082 aplicada não há alerta.
  Future<AdminPartnerAlerts> fetchPartnerAlerts() async {
    try {
      final data = await _client.rpc('admin_partner_alerts');
      final rows = data as List;
      if (rows.isEmpty) return AdminPartnerAlerts.none;
      return AdminPartnerAlerts.fromJson(
        (rows.first as Map).cast<String, dynamic>(),
      );
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') {
        return AdminPartnerAlerts.none;
      }
      rethrow;
    }
  }

  /// Envia a foto para `partner-images` e devolve o caminho.
  Future<String> uploadPartnerImage({
    required String folder,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final extension = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final path = '$folder/${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _client.storage
        .from('partner-images')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return path;
  }

  /// Apaga uma foto antiga. Falhar aqui só deixa um ficheiro órfão.
  Future<void> removePartnerImage(String path) async {
    try {
      await _client.storage.from('partner-images').remove([path]);
    } catch (_) {}
  }

  Future<List<AdminMapZone>> fetchMapZones({
    int days = adminZoneDays,
    int cellKm = adminZoneCellKm,
  }) async {
    final data = await _client.rpc(
      'admin_map_zones',
      params: {'p_days': days, 'p_cell_km': cellKm},
    );
    return (data as List)
        .map((e) => AdminMapZone.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }
}
