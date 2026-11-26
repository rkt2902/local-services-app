import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/fuel_usage_model.dart';
import '../data/fuel_usage_repository.dart';

final fuelUsageRepositoryProvider = Provider<FuelUsageRepository>(
  (ref) => FuelUsageRepository(ref.watch(supabaseClientProvider)),
);

final fuelTypesProvider = FutureProvider<List<FuelType>>(
  (ref) => ref.read(fuelUsageRepositoryProvider).fetchFuelTypes(),
);

/// As respostas do Profissional autenticado (vazio quando nunca respondeu).
final myFuelUsageProvider = FutureProvider<List<FuelUsageEntry>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Future.value(const []);
  return ref.read(fuelUsageRepositoryProvider).fetchMyUsage();
});
