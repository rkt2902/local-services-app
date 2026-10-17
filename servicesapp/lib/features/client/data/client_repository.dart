import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/picked_photo.dart';
import 'client_profile_model.dart';
import '../../../core/config/storage_urls.dart';

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

  Future<Map<String, String>> fetchClientBasicInfo(String clientId) async {
    final data = await _client
        .from('profiles')
        .select('full_name, phone, avatar_url')
        .eq('id', clientId)
        .maybeSingle();
    if (data == null) return {'full_name': '', 'phone': '', 'avatar_url': ''};
    return {
      'full_name': data['full_name'] as String? ?? '',
      'phone': data['phone'] as String? ?? '',
      'avatar_url': StorageUrls.trustedOrEmpty(data['avatar_url'] as String?),
    };
  }
}
