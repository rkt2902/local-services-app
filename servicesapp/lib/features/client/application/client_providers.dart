import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/provider_cache.dart';
import '../../auth/application/auth_providers.dart';
import '../data/client_repository.dart';
import '../data/client_profile_model.dart';

final clientRepositoryProvider = Provider<ClientRepository>(
  (ref) => ClientRepository(ref.watch(supabaseClientProvider)),
);

final clientProfileProvider = FutureProvider<ClientProfile?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.read(clientRepositoryProvider).fetchProfile(user.id);
});

// Nome/telefone/avatar mudam raramente (edição manual de perfil) — seguro
// reaproveitar por minutos.
const _clientInfoCacheTtl = Duration(minutes: 5);

final clientBasicInfoProvider =
    FutureProvider.autoDispose.family<Map<String, String>, String>((ref, clientId) {
  if (clientId.isEmpty) return Future.value({'full_name': '', 'phone': '', 'avatar_url': ''});
  cacheFor(ref, _clientInfoCacheTtl);
  return ref.read(clientRepositoryProvider).fetchClientBasicInfo(clientId);
});
