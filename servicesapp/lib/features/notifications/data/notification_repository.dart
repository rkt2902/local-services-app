import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_model.dart';

class NotificationRepository {
  final SupabaseClient _client;
  NotificationRepository(this._client);

  Future<List<AppNotification>> fetchNotifications(String userId) async {
    final data = await _client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    return _visible(data);
  }

  Future<AppNotification?> fetchById(String notificationId) async {
    final data = await _client
        .from('notifications')
        .select()
        .eq('id', notificationId)
        .maybeSingle();
    return data == null ? null : AppNotification.fromJson(data);
  }

  Future<void> markAsRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'read': true}).eq('id', notificationId);
  }

  Future<void> markAllAsRead(String userId) async {
    await _client
        .from('notifications')
        .update({'read': true})
        .eq('user_id', userId)
        .eq('read', false);
  }

  /// "Limpar tudo" (0065): esconde e marca como lidas todas as do próprio.
  /// Devolve os ids limpos, para o "Desfazer".
  Future<List<String>> clearAll() async {
    final data = await _client.rpc('clear_my_notifications');
    return [for (final id in (data as List? ?? const [])) id as String];
  }

  /// "Desfazer" do [clearAll].
  Future<void> restore(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client.rpc('restore_my_notifications', params: {'p_ids': ids});
  }

  /// Tira as limpas no Dart e não na query: assim a lista continua a
  /// funcionar antes de a 0065 (coluna `cleared_at`) estar aplicada.
  static List<AppNotification> _visible(dynamic data) => [
        for (final e in data as List)
          if (AppNotification.fromJson(e) case final n when !n.cleared) n,
      ];

  /// Streams only unread notifications — keeps the channel lightweight and
  /// ensures the badge count shrinks automatically when items are marked read.
  ///
  /// `.limit(50)`: sem limite, o stream trazia o histórico inteiro do
  /// utilizador (lidas incluídas) e só filtrava no Dart. Um jardineiro
  /// recebe uma `new_job_in_radius` por cada pedido na zona, por isso
  /// crescia sem fim. As 50 mais recentes chegam para o badge e para o
  /// `notificationSync` (review 2026-10-16, P1).
  Stream<List<AppNotification>> streamNotifications(String userId) {
    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50)
        .map((data) => data
            .map((e) => AppNotification.fromJson(e))
            .where((n) => !n.read && !n.cleared)
            .toList());
  }

  /// One-time fetch of the full history (read + unread) for the history screen.
  Future<List<AppNotification>> fetchAllNotifications(String userId) async {
    final data = await _client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    return _visible(data);
  }

  /// "Dicas da época" (0062). Sem linha guardada vale `true`.
  Future<bool> fetchSeasonalTipsEnabled() async {
    final data = await _client.rpc('get_my_notification_preferences');
    final rows = data as List<dynamic>;
    if (rows.isEmpty) return true;
    return (rows.first as Map<String, dynamic>)['seasonal_tips'] as bool? ??
        true;
  }

  Future<void> setSeasonalTips(bool enabled) async {
    await _client.rpc('set_seasonal_tips', params: {'p_enabled': enabled});
  }
}
