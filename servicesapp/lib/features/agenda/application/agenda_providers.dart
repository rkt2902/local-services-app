import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/provider_cache.dart';
import '../../auth/application/auth_providers.dart';
import '../data/agenda_entry_model.dart';
import '../data/agenda_repository.dart';

final agendaRepositoryProvider = Provider<AgendaRepository>(
  (ref) => AgendaRepository(ref.watch(supabaseClientProvider)),
);

/// Entradas da agenda num intervalo de dias `(de, até)`, inclusivo, no
/// máximo 62 dias. Chave em datas sem hora, para Hoje, Semana e Mês do
/// mesmo período reaproveitarem a cache. 45 s, como o job em si.
final agendaRangeProvider = FutureProvider.autoDispose
    .family<List<AgendaEntry>, (DateTime, DateTime)>((ref, range) {
      final user = ref.watch(currentUserProvider);
      if (user == null) return Future.value([]);
      cacheFor(ref, const Duration(seconds: 45));
      final (from, to) = range;
      return ref.read(agendaRepositoryProvider).fetchAgenda(from: from, to: to);
    });

/// Mês inteiro de [day], a chave usada pelo Hoje: desliza entre dias sem
/// novo pedido e o calendário reaproveita a mesma leitura.
(DateTime, DateTime) agendaMonthRange(DateTime day) => (
  DateTime(day.year, day.month),
  DateTime(day.year, day.month + 1, 0),
);
