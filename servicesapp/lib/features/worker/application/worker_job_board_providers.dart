import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/worker_job_board_entry_model.dart';
import '../data/worker_job_board_repository.dart';

final workerJobBoardRepositoryProvider = Provider<WorkerJobBoardRepository>(
  (ref) => WorkerJobBoardRepository(ref.watch(supabaseClientProvider)),
);

/// Página paginada do board unificado (responsável + ajudante) de
/// `worker_jobs_screen.dart`. Chave: `(tab, página 0-based)`, onde `tab` é
/// o valor RPC (`pending`/`scheduled`/`completed`) — ver
/// `get_worker_job_board` (migration 0035).
final workerJobBoardPageProvider = FutureProvider.family<
    List<WorkerJobBoardEntry>, (String, int)>((ref, args) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Future.value([]);
  final (tab, page) = args;
  return ref
      .read(workerJobBoardRepositoryProvider)
      .fetchJobBoard(tab: tab, page: page);
});
