import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'worker_profile_model.dart';
import 'service_type_model.dart';

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
      avatarUrl: profileData['avatar_url'] as String?,
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
        .select()
        .eq('active', true);
    return (data as List).map((e) => ServiceType.fromJson(e)).toList();
  }

  Future<void> createProfile(WorkerProfile profile) async {
    await _client.from('profiles').update({
      'full_name': profile.fullName,
      'phone': profile.phone,
    }).eq('id', profile.profileId);

    await _client.from('worker_profiles').upsert({
      'profile_id': profile.profileId,
      ...profile.toWorkerJson(),
    });

    await _syncServiceTypes(profile.profileId, profile.serviceTypeIds);
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

    await _syncServiceTypes(profile.profileId, profile.serviceTypeIds);
  }

  Future<void> _syncServiceTypes(
      String workerId, List<String> serviceTypeIds) async {
    await _client.rpc('sync_worker_service_types', params: {
      'p_worker_id': workerId,
      'p_service_type_ids': serviceTypeIds,
    });
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
      'avatar_url': data['avatar_url'] as String? ?? '',
    };
  }

  Future<String> fetchWorkerName(String workerId) async {
    if (workerId.isEmpty) return '';
    final data = await _client
        .from('profiles')
        .select('full_name')
        .eq('id', workerId)
        .maybeSingle();
    return data?['full_name'] as String? ?? '';
  }

  Future<Map<String, String?>> fetchProfileSummary(String profileId) async {
    if (profileId.isEmpty) return {};
    final data = await _client
        .from('profiles')
        .select('full_name, avatar_url')
        .eq('id', profileId)
        .maybeSingle();
    if (data == null) return {};
    return {
      'full_name': data['full_name'] as String?,
      'avatar_url': data['avatar_url'] as String?,
    };
  }

  Future<String> uploadAvatar(String userId, File file) async {
    final path = '$userId.jpg';
    await _client.storage.from('avatars').upload(
          path,
          file,
          fileOptions: const FileOptions(upsert: true),
        );
    return _client.storage.from('avatars').getPublicUrl(path);
  }
}
