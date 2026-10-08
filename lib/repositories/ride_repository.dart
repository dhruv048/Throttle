import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/local_ride_store.dart';
import '../services/ride_events.dart';
import 'bike_repository.dart';

class RideRepository {
  RideRepository({
    SupabaseClient? client,
    LocalRideStore? store,
    BikeRepository? bikes,
  })  : _client = client ?? Supabase.instance.client,
        _store = store ?? LocalRideStore(),
        _bikes = bikes ?? BikeRepository();

  final SupabaseClient _client;
  final LocalRideStore _store;
  final BikeRepository _bikes;
  final _uuid = const Uuid();

  /// Save ride + track locally first, then attempt upload.
  /// Returns the local draft; [PendingRide.synced] is true if cloud upload succeeded.
  Future<PendingRide> shareRide({
    required String title,
    required RideVisibility visibility,
    required double distanceKm,
    required int movingTimeSecs,
    required double avgSpeedKmh,
    required double maxSpeedKmh,
    required String bikeName,
    String? bikeId,
    double elevationM = 0,
    required List<TrackPoint> points,
    DateTime? startedAt,
    DateTime? endedAt,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw const AuthException('Sign in to share a ride');
    }

    // No network calls before this point: the ride must hit the device first.
    // A missing bikeId is resolved at upload time.
    final pending = PendingRide(
      localId: _uuid.v4(),
      userId: uid,
      title: title,
      visibility: visibility,
      distanceKm: distanceKm,
      movingTimeSecs: movingTimeSecs,
      avgSpeedKmh: avgSpeedKmh,
      maxSpeedKmh: maxSpeedKmh,
      elevationM: elevationM,
      bikeName: bikeName,
      bikeId: bikeId,
      points: points,
      createdAt: DateTime.now(),
      startedAt: startedAt,
      endedAt: endedAt ?? DateTime.now(),
    );

    await _store.enqueue(pending);

    try {
      final remote = await uploadPending(pending);
      await _store.markSynced(pending.localId, remote.id);
      pending.synced = true;
      pending.remoteId = remote.id;
    } catch (_) {
      // Kept in local queue for RideSyncService.
    }

    RideEvents.notify();
    return pending;
  }

  Future<RideRecord> uploadPending(PendingRide pending) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw const AuthException('Not signed in');
    }
    if (pending.userId != null && pending.userId != uid) {
      // Recorded under another account; RLS would reject it. Wait for that rider.
      throw const AuthException('Ride belongs to a different account');
    }

    // Idempotent: if already uploaded with this local_id, return it.
    final existing = await _client
        .from('rides')
        .select()
        .eq('user_id', uid)
        .eq('local_id', pending.localId)
        .maybeSingle();
    if (existing != null) {
      final ride = RideRecord.fromJson(Map<String, dynamic>.from(existing));
      // Ensure track exists if network previously failed right after creating the ride
      final trackExists = await _client
          .from('ride_tracks')
          .select('id')
          .eq('ride_id', ride.id)
          .maybeSingle();
      if (trackExists == null && pending.points.isNotEmpty) {
        await _insertTrack(ride.id, pending.points);
      }
      return ride;
    }

    // Every ride is credited to a bike: the one picked by name, else primary.
    var bikeId = pending.bikeId;
    if (bikeId == null) {
      final bikes = await _bikes.listForUser(uid);
      bikeId = bikes.where((b) => b.name == pending.bikeName).firstOrNull?.id ??
          bikes.firstOrNull?.id; // listForUser puts the primary first
    }

    final Map<String, dynamic> rideRow;
    try {
      rideRow = await _client
          .from('rides')
          .insert({
            'user_id': uid,
            'bike_id': bikeId,
            'title': pending.title,
            'visibility': pending.visibility.dbValue,
            'distance_km': pending.distanceKm,
            'moving_time_secs': pending.movingTimeSecs,
            'avg_speed_kmh': pending.avgSpeedKmh,
            'max_speed_kmh': pending.maxSpeedKmh,
            'elevation_m': pending.elevationM,
            'started_at': pending.startedAt?.toIso8601String(),
            'ended_at': pending.endedAt?.toIso8601String(),
            'local_id': pending.localId,
          })
          .select()
          .single();
    } on PostgrestException catch (e) {
      // Another upload of this draft (share vs. background sync) won the race.
      if (e.code == '23505') return uploadPending(pending);
      rethrow;
    }

    final ride = RideRecord.fromJson(Map<String, dynamic>.from(rideRow));

    await _insertTrack(ride.id, pending.points);

    return ride;
  }

  Future<List<RideRecord>> listForUser(String userId, {int limit = 30}) async {
    final rows = await _client
        .from('rides')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((e) => RideRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _insertTrack(String rideId, List<TrackPoint> points) {
    return _client.from('ride_tracks').upsert(
      {
        'ride_id': rideId,
        'points': points.map((p) => p.toJson()).toList(),
      },
      onConflict: 'ride_id',
      ignoreDuplicates: true,
    );
  }

  static const _feedSelect = '*, '
      'rider:profiles(id, username, display_name, avatar_url, city), '
      'bike:bikes(name, photo_url), '
      'track:ride_tracks(points)';

  /// Rides the current viewer may see (RLS applies visibility), newest first.
  Future<List<FeedItem>> feed({int limit = 30}) async {
    final rows = await _client
        .from('rides')
        .select(_feedSelect)
        .order('created_at', ascending: false)
        .limit(limit) as List;
    return _toFeedItems(rows);
  }

  /// The signed-in rider's own rides, newest first, one page at a time.
  Future<List<FeedItem>> myRides({int offset = 0, int limit = 20}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _client
        .from('rides')
        .select(_feedSelect)
        .eq('user_id', uid)
        // Ride time, not upload time: offline rides can sync days later.
        .order('started_at', ascending: false, nullsFirst: false)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1) as List;
    return _toFeedItems(rows);
  }

  Future<int> countForUser(String userId) =>
      _client.from('rides').count(CountOption.exact).eq('user_id', userId);

  /// Lightweight rows of every ride the rider has uploaded, for totals.
  Future<List<RideRecord>> myRideHistory() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    const page = 1000; // PostgREST max_rows
    final out = <RideRecord>[];
    for (var from = 0;; from += page) {
      final rows = await _client
          .from('rides')
          .select('id, user_id, bike_id, title, distance_km, moving_time_secs, '
              'elevation_m, started_at, ended_at, created_at, local_id')
          .eq('user_id', uid)
          .order('created_at')
          .range(from, from + page - 1) as List;
      out.addAll(rows.map(
          (e) => RideRecord.fromJson(Map<String, dynamic>.from(e as Map))));
      if (rows.length < page) return out;
    }
  }

  /// Rides saved on this device for the signed-in rider that haven't synced.
  Future<List<PendingRide>> myPendingRides() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    final pending = await _store.pendingUnsynced();
    return pending.where((r) => r.userId == null || r.userId == uid).toList();
  }

  Future<List<FeedItem>> _toFeedItems(List rows) async {
    final liked = <String>{};
    final uid = _client.auth.currentUser?.id;
    if (uid != null && rows.isNotEmpty) {
      final kudos = await _client
          .from('kudos')
          .select('ride_id')
          .eq('user_id', uid)
          .inFilter('ride_id', rows.map((r) => r['id']).toList()) as List;
      liked.addAll(kudos.map((k) => k['ride_id'] as String));
    }

    return rows.map((e) {
      final json = Map<String, dynamic>.from(e as Map);
      return FeedItem.fromJson(json, likedByMe: liked.contains(json['id']));
    }).toList();
  }

  Future<void> giveKudos(String rideId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Not signed in');
    await _client.from('kudos').upsert({'ride_id': rideId, 'user_id': uid},
        onConflict: 'ride_id,user_id', ignoreDuplicates: true);
  }

  Future<void> removeKudos(String rideId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Not signed in');
    await _client
        .from('kudos')
        .delete()
        .eq('ride_id', rideId)
        .eq('user_id', uid);
  }

  Future<List<TrackPoint>> trackForRide(String rideId) async {
    final row = await _client
        .from('ride_tracks')
        .select('points')
        .eq('ride_id', rideId)
        .maybeSingle();
    if (row == null) return [];
    final points = row['points'] as List? ?? [];
    return points
        .map((e) => TrackPoint.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Deletes a ride saved from this phone, wherever it currently lives.
  Future<void> deleteSavedRide(PendingRide ride) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Not signed in');
    final stored = (await _store.loadAll())
        .where((r) => r.localId == ride.localId)
        .firstOrNull;
    final uploaded = ride.synced || (stored?.synced ?? false);
    try {
      // By local_id, so it also catches a background sync racing this delete.
      await _client
          .from('rides')
          .delete()
          .eq('user_id', uid)
          .eq('local_id', ride.localId);
    } catch (_) {
      // Offline. Fine if it never left the phone; otherwise keep it.
      if (uploaded) rethrow;
    }
    await _store.remove(ride.localId);
    RideEvents.notify();
  }

  Future<void> deleteRide(String rideId) async {
    await _client.from('rides').delete().eq('id', rideId);
    RideEvents.notify();
  }
}
