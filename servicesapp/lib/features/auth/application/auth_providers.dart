import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/auth_repository.dart';

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges,
);

/// Só reconstrói quando o utilizador muda (login, logout, troca de conta).
/// Antes reagia a todos os eventos de auth, incluindo o `tokenRefreshed`
/// de hora a hora, e cada `User` novo fazia refazer o fetch de todos os
/// providers que dependem deste e reabrir o stream Realtime de
/// notificações (review 2026-10-16, P2).
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(
    authStateProvider.select((s) => s.asData?.value.session?.user.id),
  );
  return ref.read(authRepositoryProvider).currentUser;
});

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider)?.id;
});
