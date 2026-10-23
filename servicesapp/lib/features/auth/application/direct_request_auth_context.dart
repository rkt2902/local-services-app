import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Pedido pelo cartão de um jardineiro à espera de login ou registo (A7).
/// Quem abre `/w/:id` sem sessão e toca em "Pedir orçamento" passa pelo
/// login/registo normal; isto fica guardado no dispositivo (sobrevive à
/// confirmação do email noutra aba ou a fechar a app) e, já como cliente,
/// a app volta ao pedido para este jardineiro.
class DirectRequestAuthContext {
  const DirectRequestAuthContext({
    required this.workerId,
    required this.workerName,
    required this.savedAt,
    this.workerAvatarUrl = '',
    this.visitId,
  });

  final String workerId;
  final String workerName;
  final String workerAvatarUrl;

  /// Visita ao cartão registada no servidor (`log_worker_card_visit`), para
  /// ligar a conta nova ao QR/link de onde veio.
  final String? visitId;
  final DateTime savedAt;

  /// Passado um dia já não se volta ao pedido sozinho: quem entra outra vez
  /// noutro dia não espera cair no wizard.
  static const maxAge = Duration(hours: 24);

  bool isFresh(DateTime now) => now.difference(savedAt) < maxAge;

  Map<String, dynamic> toJson() => {
        'worker_id': workerId,
        'worker_name': workerName,
        'worker_avatar_url': workerAvatarUrl,
        'visit_id': ?visitId,
        'saved_at': savedAt.toUtc().toIso8601String(),
      };

  static DirectRequestAuthContext? fromJson(Map<String, dynamic> json) {
    final workerId = json['worker_id'];
    final savedAt = DateTime.tryParse(json['saved_at'] as String? ?? '');
    if (workerId is! String || workerId.isEmpty || savedAt == null) {
      return null;
    }
    return DirectRequestAuthContext(
      workerId: workerId,
      workerName: json['worker_name'] as String? ?? '',
      workerAvatarUrl: json['worker_avatar_url'] as String? ?? '',
      visitId: json['visit_id'] as String?,
      savedAt: savedAt,
    );
  }
}

/// Guarda o pedido pendente e a chave anónima do dispositivo (para o
/// servidor não contar duas vezes a mesma visita ao cartão).
class DirectRequestAuthStore {
  const DirectRequestAuthStore();

  static const _pendingKey = 'card_direct_request_pending';
  static const _deviceKey = 'card_visit_device_key';

  Future<DirectRequestAuthContext?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey);
    if (raw == null) return null;
    try {
      return DirectRequestAuthContext.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(DirectRequestAuthContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingKey, jsonEncode(context.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey);
  }

  /// Id aleatório deste dispositivo, criado na primeira vez. Não identifica
  /// a pessoa; só serve para juntar visitas repetidas ao mesmo cartão.
  Future<String> deviceKey() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await prefs.setString(_deviceKey, created);
    return created;
  }
}

final directRequestAuthStoreProvider = Provider<DirectRequestAuthStore>(
  (_) => const DirectRequestAuthStore(),
);

/// Pedido pelo cartão à espera de sessão, para os banners do login e do
/// registo ("Vais pedir orçamento ao Rui") e para voltar ao pedido.
class DirectRequestAuthNotifier
    extends AsyncNotifier<DirectRequestAuthContext?> {
  @override
  Future<DirectRequestAuthContext?> build() async {
    try {
      final pending = await ref.read(directRequestAuthStoreProvider).load();
      if (pending == null || !pending.isFresh(DateTime.now())) return null;
      return pending;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(DirectRequestAuthContext context) async {
    state = AsyncValue.data(context);
    try {
      await ref.read(directRequestAuthStoreProvider).save(context);
    } catch (_) {
      // Fica só em memória: dá para voltar ao pedido nesta execução.
    }
  }

  /// Lê e apaga o pedido pendente, para só se voltar a ele uma vez.
  Future<DirectRequestAuthContext?> take() async {
    final pending = state.asData?.value ?? await future;
    state = const AsyncValue.data(null);
    try {
      await ref.read(directRequestAuthStoreProvider).clear();
    } catch (_) {}
    return pending;
  }

  Future<void> clear() async {
    state = const AsyncValue.data(null);
    try {
      await ref.read(directRequestAuthStoreProvider).clear();
    } catch (_) {}
  }
}

final directRequestAuthProvider = AsyncNotifierProvider<
    DirectRequestAuthNotifier, DirectRequestAuthContext?>(
  DirectRequestAuthNotifier.new,
);
