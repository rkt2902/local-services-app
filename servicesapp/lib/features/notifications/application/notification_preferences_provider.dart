import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import 'notification_providers.dart';

/// "Dicas da época" ligadas (0062). Ficheiro à parte de
/// `notification_providers.dart` para não misturar com a sincronização.
final seasonalTipsEnabledProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return true;
  return ref.read(notificationRepositoryProvider).fetchSeasonalTipsEnabled();
});
