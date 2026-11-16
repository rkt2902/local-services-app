import 'package:supabase_flutter/supabase_flutter.dart';

import 'partner_model.dart';

class PartnerRepository {
  const PartnerRepository(this._client);

  final SupabaseClient _client;

  /// Parceiros ativos e visíveis (`get_partners`, 0082). Sem a 0082
  /// aplicada (função em falta) devolve lista vazia: a tab não aparece.
  Future<List<Partner>> fetchPartners() async {
    try {
      final data = await _client.rpc('get_partners');
      return (data as List)
          .map((e) => Partner.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return const [];
      rethrow;
    }
  }
}
