import 'package:supabase_flutter/supabase_flutter.dart';

import 'fleet_card_model.dart';

class FleetCardRepository {
  const FleetCardRepository(this._client);

  final SupabaseClient _client;

  /// Sem UNIQUE em `worker_id` (migration 0037 — de propósito, ver
  /// comentário na migration): o worker pode ter várias linhas ao longo do
  /// tempo. "O estado atual" é sempre a mais recente, nunca "a" linha.
  Future<FleetCard?> fetchMyFleetCard(String workerId) async {
    final data = await _client
        .from('worker_fleet_cards')
        .select()
        .eq('worker_id', workerId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (data == null) return null;
    return FleetCard.fromJson(data);
  }

  /// Cria sempre com `status = 'pending'` — não há caminho nenhum na app
  /// para o worker definir outro estado (RLS também bloquearia: sem
  /// policy de UPDATE para 'authenticated').
  Future<void> createFleetCard({
    required String workerId,
    required String barcodeValue,
    String? cardNumber,
    String? holderName,
  }) async {
    await _client.from('worker_fleet_cards').insert({
      'worker_id': workerId,
      'barcode_value': barcodeValue,
      if (cardNumber != null && cardNumber.isNotEmpty) 'card_number': cardNumber,
      if (holderName != null && holderName.isNotEmpty) 'holder_name': holderName,
      'status': 'pending',
    });
  }
}
