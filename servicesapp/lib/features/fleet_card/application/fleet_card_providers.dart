import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/fleet_card_model.dart';
import '../data/fleet_card_repository.dart';

final fleetCardRepositoryProvider = Provider<FleetCardRepository>(
  (ref) => FleetCardRepository(ref.watch(supabaseClientProvider)),
);

/// A linha mais recente do worker autenticado — `null` quando nunca pediu
/// nenhum cartão. Ver nota em `FleetCardRepository.fetchMyFleetCard`.
final myFleetCardProvider = FutureProvider<FleetCard?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Future.value(null);
  return ref.read(fleetCardRepositoryProvider).fetchMyFleetCard(user.id);
});
