import 'package:supabase_flutter/supabase_flutter.dart';

import 'agenda_entry_model.dart';

/// Agenda do jardineiro (0064). Leitura por `get_worker_agenda`; as entradas
/// de fora da app escrevem-se direto na tabela, com RLS só do dono. O
/// `worker_id` nunca é enviado: vem do DEFAULT `auth.uid()`.
class AgendaRepository {
  const AgendaRepository(this._client);

  final SupabaseClient _client;

  /// Intervalo máximo de 62 dias (a RPC recusa mais).
  Future<List<AgendaEntry>> fetchAgenda({
    required DateTime from,
    required DateTime to,
  }) async {
    final data = await _client.rpc(
      'get_worker_agenda',
      params: {'p_from': _date(from), 'p_to': _date(to)},
    );
    return (data as List)
        .map((e) => AgendaEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// "Este e os seguintes": divide a série e devolve o id da nova, que
  /// começa em [fromDate]. As mudanças aplicam-se depois à nova série.
  Future<String> splitSeries({
    required String entryId,
    required DateTime fromDate,
  }) async {
    final id = await _client.rpc(
      'split_calendar_series',
      params: {'p_entry_id': entryId, 'p_from_date': _date(fromDate)},
    );
    return id as String;
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
