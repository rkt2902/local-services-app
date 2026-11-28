import 'package:supabase_flutter/supabase_flutter.dart';

/// Link "não quero receber" dos convites por email (0085). Funciona sem
/// sessão: a RPC `invite_optout` só aceita o token do próprio email.
class InviteOptoutRepository {
  const InviteOptoutRepository(this._client);

  final SupabaseClient _client;

  /// `true` = registado (ou já estava). `false` = o token não existe.
  Future<bool> optout(String token) async {
    final data = await _client.rpc('invite_optout', params: {'p_token': token});
    return data == true;
  }
}

/// O token do link tem a forma de um uuid. Outra coisa nem vai à BD.
bool inviteOptoutTokenLooksValid(String? token) =>
    token != null &&
    RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(token.trim());
