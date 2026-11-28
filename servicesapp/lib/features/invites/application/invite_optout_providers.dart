import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/invite_optout_repository.dart';

final inviteOptoutRepositoryProvider = Provider<InviteOptoutRepository>(
  (ref) => InviteOptoutRepository(ref.watch(supabaseClientProvider)),
);
