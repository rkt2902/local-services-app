import 'package:supabase_flutter/supabase_flutter.dart';

/// Tokens FCM do dispositivo — tabela `device_tokens` (migration 0040).
/// Escrita só via RPC (SECURITY DEFINER, filtra por auth.uid()).
class DeviceTokenRepository {
  final SupabaseClient _client;
  DeviceTokenRepository(this._client);

  Future<void> register(String token, String platform) async {
    await _client.rpc('register_device_token', params: {
      'p_token': token,
      'p_platform': platform,
    });
  }

  Future<void> unregister(String token) async {
    await _client.rpc('unregister_device_token', params: {'p_token': token});
  }
}
