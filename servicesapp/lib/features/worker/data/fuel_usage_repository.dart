import 'package:supabase_flutter/supabase_flutter.dart';

import 'fuel_usage_model.dart';

/// Consumo de combustível do Profissional (migration 0084). As linhas só
/// se leem e gravam pelas RPCs, sempre do próprio (auth.uid() na BD).
class FuelUsageRepository {
  const FuelUsageRepository(this._client);

  final SupabaseClient _client;

  Future<List<FuelType>> fetchFuelTypes() async {
    final data = await _client
        .from('fuel_types')
        .select('id, name, icon')
        .order('sort_order');
    return (data as List)
        .map((e) => FuelType.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<FuelUsageEntry>> fetchMyUsage() async {
    final data = await _client.rpc('get_my_fuel_usage');
    return (data as List)
        .map((e) => FuelUsageEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Substitui tudo de uma vez; uma lista vazia limpa as respostas.
  Future<void> saveMyUsage(List<FuelUsageEntry> entries) async {
    await _client.rpc('set_my_fuel_usage', params: {
      'p_items': entries.map((e) => e.toJson()).toList(),
    });
  }
}
