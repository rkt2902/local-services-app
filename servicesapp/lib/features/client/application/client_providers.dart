import 'package:flutter_riverpod/flutter_riverpod.dart';
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

final clientBasicInfoProvider =
    FutureProvider.family<Map<String, String>, String>((ref, clientId) {
  if (clientId.isEmpty) return Future.value({'full_name': '', 'phone': ''});
  return ref.read(clientRepositoryProvider).fetchClientBasicInfo(clientId);
});
