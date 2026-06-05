import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'client_profile_model.dart';

class ClientRepository {
  final SupabaseClient _client;
  ClientRepository(this._client);

  Future<ClientProfile?> fetchProfile(String userId) async {
    final data = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (data == null) return null;
    return ClientProfile.fromJson(data);
  }

  Future<void> updateProfile(String userId, ClientProfile profile) async {
    await _client.from('profiles').update(profile.toJson()).eq('id', userId);
  }

  Future<String> uploadAvatar(String userId, File file) async {
    final path = 'avatars/$userId.jpg';
    await _client.storage.from('avatars').upload(
          path,
          file,
          fileOptions: const FileOptions(upsert: true),
        );
    return _client.storage.from('avatars').getPublicUrl(path);
  }
}
