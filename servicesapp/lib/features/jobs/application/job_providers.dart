import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/job_repository.dart';

// serviceTypesProvider and ServiceType are reused from features/worker —
// see decisions_log.md (2026-06-08).
export '../../worker/application/worker_providers.dart'
    show serviceTypesProvider;
export '../../worker/data/service_type_model.dart' show ServiceType;

final jobRepositoryProvider = Provider<JobRepository>(
  (ref) => JobRepository(ref.watch(supabaseClientProvider)),
);
