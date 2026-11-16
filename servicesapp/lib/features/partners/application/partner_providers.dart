import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/partner_model.dart';
import '../data/partner_repository.dart';

final partnerRepositoryProvider = Provider<PartnerRepository>(
  (ref) => PartnerRepository(ref.watch(supabaseClientProvider)),
);

/// Parceiros para o jardineiro. O menu de baixo vigia isto: com lista
/// vazia (ou erro) não há botão "Parceiros".
final partnersProvider = FutureProvider<List<Partner>>((ref) {
  ref.watch(currentUserProvider);
  return ref.read(partnerRepositoryProvider).fetchPartners();
});

/// Há parceiros para mostrar? `false` enquanto carrega ou com erro.
final hasPartnersProvider = Provider<bool>(
  (ref) => ref.watch(partnersProvider).asData?.value.isNotEmpty ?? false,
);
