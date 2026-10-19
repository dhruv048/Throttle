import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../services/data_changes.dart';

/// Kudos and new followers, for the signed-in rider. The database writes
/// them (see the notifications migration); the app reads them and marks
/// them read.
class NotificationRepository {
  NotificationRepository({
    SupabaseClient? client,
    DataChanges changes = const DataChanges(),
  })  : _client = client ?? Supabase.instance.client,
        _changes = changes;

  final SupabaseClient _client;
  final DataChanges _changes;

  static const _select = '*, '
      'actor:profiles!actor_id(id, username, display_name, avatar_url, city), '
      'ride:rides(id, title)';

  /// The newest first.
  Future<List<AppNotification>> list({int limit = 50}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _client
        .from('notifications')
        .select(_select)
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(limit) as List;
    return rows
        .map((e) =>
            AppNotification.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<int> unreadCount() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return 0;
    return _client
        .from('notifications')
        .count(CountOption.exact)
        .eq('user_id', uid)
        .isFilter('read_at', null);
  }

  Future<void> markAllRead() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    await _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', uid)
        .isFilter('read_at', null);
    _changes.notifications();
  }
}
