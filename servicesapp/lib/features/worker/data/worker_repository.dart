import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/error_utils.dart';
import '../../../core/utils/picked_photo.dart';
import 'worker_profile_model.dart';
import 'worker_public_card_model.dart';
import 'worker_plan_model.dart';
import 'service_type_model.dart';
import '../../../core/config/storage_urls.dart';

class WorkerRepository {
  final SupabaseClient _client;
  WorkerRepository(this._client);

  Future<WorkerProfile?> fetchProfile(String userId) async {
    final profileData = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (profileData == null) return null;

    final workerData = await _client
        .from('worker_profiles')
        .select()
        .eq('profile_id', userId)
        .maybeSingle();
    if (workerData == null) return null;

    final serviceTypeRows = await _client
        .from('worker_service_types')
        .select('service_type_id')
        .eq('worker_id', userId);
    final serviceTypeIds = (serviceTypeRows as List)
        .map((r) => r['service_type_id'] as String)
        .toList();

    return WorkerProfile.fromJson(
      workerData,
      fullName: profileData['full_name'] as String,
      phone: profileData['phone'] as String? ?? '',
      avatarUrl:
          StorageUrls.trustedOrNull(profileData['avatar_url'] as String?),
      serviceTypeIds: serviceTypeIds,
    );
  }

  Future<bool> hasProfile(String userId) async {
    final data = await _client
        .from('worker_profiles')
        .select('profile_id')
        .eq('profile_id', userId)
        .maybeSingle();
    return data != null;
  }

  Future<List<ServiceType>> fetchServiceTypes() async {
    final data = await _client
        .from('service_types')
        .select('*, service_categories!inner(name, icon, sort_order, active)')
        .eq('active', true)
        .eq('service_categories.active', true);
    final types = (data as List).map((e) => ServiceType.fromJson(e)).toList()
      ..sort((a, b) {
        final byCategory = a.categorySortOrder.compareTo(b.categorySortOrder);
        if (byCategory != 0) return byCategory;
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
      });
    return types;
  }

  Future<void> createProfile(WorkerProfile profile) async {
    await _client.from('profiles').update({
      'full_name': profile.fullName,
      'phone': profile.phone,
      if (profile.avatarUrl != null) 'avatar_url': profile.avatarUrl,
    }).eq('id', profile.profileId);

    await _client.from('worker_profiles').upsert({
      'profile_id': profile.profileId,
      ...profile.toWorkerJson(),
    });

    await _syncServiceTypes(profile.serviceTypeIds);
  }

  Future<void> updateProfile(WorkerProfile profile) async {
    await _client.from('profiles').update({
      'full_name': profile.fullName,
      'phone': profile.phone,
      if (profile.avatarUrl != null) 'avatar_url': profile.avatarUrl,
    }).eq('id', profile.profileId);

    await _client
        .from('worker_profiles')
        .update(profile.toWorkerJson())
        .eq('profile_id', profile.profileId);

    await _syncServiceTypes(profile.serviceTypeIds);
  }

  Future<void> _syncServiceTypes(List<String> serviceTypeIds) async {
    await _client.rpc('sync_worker_service_types', params: {
      'p_service_type_ids': serviceTypeIds,
    });
  }

  /// Plano e uso do mês do próprio jardineiro (`get_my_plan`, 0060).
  /// Sem a 0060 aplicada a RPC não existe: devolve [WorkerPlan.unavailable].
  Future<WorkerPlan> fetchMyPlan() async {
    try {
      final data = await _client.rpc('get_my_plan');
      final rows = data as List;
      if (rows.isEmpty) return WorkerPlan.unavailable;
      return WorkerPlan.fromJson(rows.first as Map<String, dynamic>);
    } catch (e) {
      if (isMissingRpcError(e)) return WorkerPlan.unavailable;
      rethrow;
    }
  }

  Future<Map<String, String>> fetchWorkerBasicInfo(String workerId) async {
    if (workerId.isEmpty) return {};
    final data = await _client
        .from('profiles')
        .select('full_name, phone, avatar_url')
        .eq('id', workerId)
        .maybeSingle();
    if (data == null) return {};
    return {
      'full_name': data['full_name'] as String? ?? '',
      'phone': data['phone'] as String? ?? '',
      'avatar_url': StorageUrls.trustedOrEmpty(data['avatar_url'] as String?),
    };
  }

  Future<WorkerPublicCard?> fetchPublicCard(String workerId) async {
    final data = await _client
        .from('worker_public_card')
        .select()
        .eq('worker_id', workerId)
        .maybeSingle();
    if (data == null) return null;
    return WorkerPublicCard.fromJson(data);
  }

  /// Regista uma abertura do cartão público (0059), também sem sessão.
  /// [source]: "qr", "link" ou "app". Devolve o id da visita, ou `null`
  /// (o próprio jardineiro, ou a migration ainda por aplicar). Nunca
  /// falha: o registo não pode impedir de ver o cartão.
  Future<String?> logCardVisit({
    required String workerId,
    required String source,
    String? deviceKey,
  }) async {
    try {
      final id = await _client.rpc('log_worker_card_visit', params: {
        'p_worker_id': workerId,
        'p_source': source,
        'p_device_key': ?deviceKey,
      });
      return id as String?;
    } catch (_) {
      return null;
    }
  }

  /// Liga a visita ao cartão à conta que acabou de entrar ou de ser
  /// criada (0059). Falhas ficam em silêncio.
  Future<void> claimCardVisit(String visitId) async {
    try {
      await _client.rpc('claim_worker_card_visit', params: {
        'p_visit_id': visitId,
      });
    } catch (_) {}
  }

  Future<String> uploadAvatar(String userId, XFile file) async {
    final path = '$userId.jpg';
    final bucket = _client.storage.from('avatars');
    if (kIsWeb) {
      // Na web não há ficheiro em disco: envia os bytes do browser.
      await bucket.uploadBinary(
        path,
        await file.readAsBytes(),
        fileOptions: FileOptions(
          upsert: true,
          contentType: pickedPhotoContentType(file),
        ),
      );
    } else {
      await bucket.upload(
        path,
        File(file.path),
        fileOptions: const FileOptions(upsert: true),
      );
    }
    final url = _client.storage.from('avatars').getPublicUrl(path);
    return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
  }
}
