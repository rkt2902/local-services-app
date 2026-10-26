import 'package:supabase_flutter/supabase_flutter.dart';

import 'agenda_calendar_entry.dart';
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

  /// "Já estou livre": liberta só [day] de uma indisponibilidade. Numa
  /// série, [seriesDate] diz qual ocorrência.
  Future<void> freeDay({
    required String entryId,
    required DateTime seriesDate,
    required DateTime day,
  }) async {
    await _client.rpc(
      'free_calendar_day',
      params: {
        'p_entry_id': entryId,
        'p_series_date': _date(seriesDate),
        'p_day': _date(day),
      },
    );
  }

  /// A série inteira, para o formulário de editar. Com [occurrenceDate],
  /// também a exceção desse dia, se houver.
  Future<(CalendarEntry, CalendarException?)> fetchCalendarEntry(
    String id, {
    DateTime? occurrenceDate,
  }) async {
    final row = await _client
        .from('worker_calendar_entries')
        .select()
        .eq('id', id)
        .single();
    CalendarException? exception;
    if (occurrenceDate != null) {
      final found = await _client
          .from('worker_calendar_exceptions')
          .select()
          .eq('entry_id', id)
          .eq('occurrence_date', _date(occurrenceDate))
          .maybeSingle();
      if (found != null) exception = CalendarException.fromJson(found);
    }
    return (CalendarEntry.fromJson(row), exception);
  }

  /// Cria a entrada e devolve o id. [values] vem de
  /// `AgendaEntryForm.toRow()`; o `worker_id` é o DEFAULT `auth.uid()`.
  Future<String> createCalendarEntry(Map<String, dynamic> values) async {
    final row = await _client
        .from('worker_calendar_entries')
        .insert(values)
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> updateCalendarEntry(
    String id,
    Map<String, dynamic> values,
  ) async {
    await _client.from('worker_calendar_entries').update(values).eq('id', id);
  }

  /// Apaga a série toda (as exceções vão em cascata).
  Future<void> deleteCalendarEntry(String id) async {
    await _client.from('worker_calendar_entries').delete().eq('id', id);
  }

  /// "Só este dia": cria ou substitui a exceção de [occurrenceDate].
  Future<void> saveException({
    required String entryId,
    required DateTime occurrenceDate,
    required Map<String, dynamic> values,
  }) async {
    await _client.from('worker_calendar_exceptions').upsert({
      'entry_id': entryId,
      'occurrence_date': _date(occurrenceDate),
      ...values,
    }, onConflict: 'entry_id,occurrence_date');
  }

  /// Tira a exceção de um dia (ao mudar a série a partir dele).
  Future<void> deleteException({
    required String entryId,
    required DateTime occurrenceDate,
  }) async {
    await _client
        .from('worker_calendar_exceptions')
        .delete()
        .eq('entry_id', entryId)
        .eq('occurrence_date', _date(occurrenceDate));
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
