import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/application/auth_providers.dart';

/// Cartão da primeira abertura da Agenda (A8G): visto ou não, por conta e
/// por aparelho. A versão na chave deixa mostrar um cartão novo no futuro.
class AgendaIntroNotifier extends AsyncNotifier<bool> {
  static const _prefix = 'agenda_intro_v1_done_';

  String? get _key {
    final id = ref.read(currentUserProvider)?.id;
    return id == null ? null : '$_prefix$id';
  }

  /// `true` = já fechado ou concluído; não volta a aparecer.
  @override
  Future<bool> build() async {
    ref.watch(currentUserProvider.select((u) => u?.id));
    final key = _key;
    if (key == null) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  /// ✕, "Agora não" ou o primeiro trabalho guardado pelo cartão.
  Future<void> markDone() async {
    state = const AsyncData(true);
    final key = _key;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }
}

final agendaIntroDoneProvider =
    AsyncNotifierProvider<AgendaIntroNotifier, bool>(AgendaIntroNotifier.new);
