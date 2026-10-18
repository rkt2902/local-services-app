import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'job_providers.dart';

/// Pull-to-refresh do Início e dos Pedidos do cliente: volta a ler a lista
/// e espera pela resposta (o indicador fica a rodar até lá). Um erro não
/// rebenta o gesto: o próprio ecrã já mostra o estado de erro do provider.
Future<void> refreshClientJobs(WidgetRef ref) async {
  ref.invalidate(clientJobsProvider);
  try {
    await ref.read(clientJobsProvider.future);
  } catch (_) {}
}
