import 'package:supabase_flutter/supabase_flutter.dart';

import 'worker_job_board_entry_model.dart';

class WorkerJobBoardRepository {
  const WorkerJobBoardRepository(this._client);

  final SupabaseClient _client;

  /// `tab` é um dos valores aceites por `get_worker_job_board`:
  /// `pending` | `scheduled` | `completed`.
  Future<List<WorkerJobBoardEntry>> fetchJobBoard({
    required String tab,
    required int page,
    int pageSize = 20,
  }) async {
    final data = await _client.rpc('get_worker_job_board', params: {
      'p_tab': tab,
      'p_page': page,
      'p_page_size': pageSize,
    });
    return (data as List)
        .map((e) => WorkerJobBoardEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
