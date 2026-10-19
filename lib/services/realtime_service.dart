import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data_changes.dart';

/// Streams database changes made anywhere (other riders, other devices,
/// server triggers) into [DataChanges], so open screens update live.
///
/// Supabase applies each subscriber's row-level security: a rider only gets
/// changes for rides they're allowed to see.
class RealtimeService {
  RealtimeService({
    SupabaseClient? client,
    DataChanges changes = const DataChanges(),
  })  : _client = client ?? Supabase.instance.client,
        _changes = changes;

  final SupabaseClient _client;
  final DataChanges _changes;
  RealtimeChannel? _channel;
  String? _uid;

  void start(String uid) {
    if (_uid == uid && _channel != null) return;
    stop();
    _uid = uid;
    PostgresChangeFilter mine(String column) => PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: column,
          value: uid,
        );
    _channel = _client
        .channel('throttle-live-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rides',
          callback: _onRide,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bikes',
          filter: mine('user_id'),
          callback: (_) => _changes.bikes(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'follows',
          filter: mine('following_id'),
          callback: (_) => _changes.follows(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: mine('user_id'),
          callback: (_) => _changes.notifications(),
        )
        .subscribe((status, error) {
      if (error != null) debugPrint('Realtime $status: $error');
    });
  }

  void stop() {
    final channel = _channel;
    _channel = null;
    _uid = null;
    if (channel != null) _client.removeChannel(channel);
  }

  void _onRide(PostgresChangePayload change) {
    switch (change.eventType) {
      case PostgresChangeEvent.insert:
        final id = change.newRecord['id'] as String?;
        if (id == null) return;
        _changes.rideAdded(id);
        if (change.newRecord['user_id'] == _uid) _changes.rides();
      case PostgresChangeEvent.update:
        final row = change.newRecord;
        final id = row['id'] as String?;
        if (id == null) return;
        _changes.rideUpdated(RideUpdate(
          id: id,
          kudosCount: (row['kudos_count'] as num?)?.toInt(),
          commentsCount: (row['comments_count'] as num?)?.toInt(),
        ));
      case PostgresChangeEvent.delete:
        // Deletes carry only the primary key.
        final id = change.oldRecord['id'] as String?;
        if (id != null) _changes.rideDeleted(id);
      case PostgresChangeEvent.all:
        break;
    }
  }
}
