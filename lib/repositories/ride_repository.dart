import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../services/achievements.dart';
import '../services/data_changes.dart';
import '../services/db_log.dart';
import '../services/local_ride_store.dart';
import 'bike_repository.dart';
import 'journal_repository.dart';

class RideRepository {
  RideRepository({
    SupabaseClient? client,
    LocalRideStore? store,
    BikeRepository? bikes,
    JournalRepository? journal,
    DataChanges changes = const DataChanges(),
  })  : _client = client ?? Supabase.instance.client,
        _store = store ?? LocalRideStore(),
        _bikes = bikes ?? BikeRepository(),
        _journal = journal ?? JournalRepository(client: client),
        _changes = changes;

  final SupabaseClient _client;
  final LocalRideStore _store;
  final BikeRepository _bikes;
  final JournalRepository _journal;
  final DataChanges _changes;

  /// Public bucket for ride card images, one folder per rider.
  static const cardBucket = 'ride-cards';

  /// Rides (by local id) whose card or photos are uploading right now, so a
  /// save and a background sync don't both upload them.
  static final _uploadingExtras = <String>{};

  /// Rides whose photos changed while they were uploading: another pass.
  static final _mediaAgain = <String>{};

  /// Saves a finished ride to the rider's profile with the visibility it
  /// carries: on the phone first (instantly), then uploaded, or synced later
  /// if offline. Returns the saved ride; [PendingRide.synced] is true if it
  /// uploaded.
  ///
  /// Only the ride and its track hold the save up. Its ride card ([card],
  /// or one added later with [setCard]) and photos (already kept on the
  /// phone, see [LocalRideStore.saveMedia]) go up after it.
  ///
  /// Saving a ride that was saved before (resumed and finished again)
  /// brings the uploaded one up to date.
  Future<PendingRide> saveRide(PendingRide ride, {Uint8List? card}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw const AuthException('Sign in to save a ride');
    }

    // No network calls before this point: the ride must hit the device first.
    // A missing bikeId is resolved at upload time.
    final before = await _store.find(ride.localId);
    final pending = ride.copyWith(
      userId: uid,
      synced: false,
      remoteId: before?.remoteId,
      hasCard: card != null || ride.hasCard,
    );
    if (card != null) {
      await _store.saveCard(pending.localId, card);
      pending.cardImageUrl = null; // the new one goes up
    }
    await _store.enqueue(pending);
    await _store.clearDraft();
    // Shows up right away (as "waiting to sync") in the rider's lists.
    _changes.rides();

    try {
      final remote = await uploadPending(pending);
      await _store.markSynced(pending.localId, remote.id);
      pending.synced = true;
      pending.remoteId = remote.id;
      _changes.rides();
      _changes.bikes(); // the server credited the bike's km
      unawaited(_uploadExtras(pending));
    } catch (e) {
      // Kept in local queue for RideSyncService.
      debugPrint('Ride upload deferred: $e');
    }

    return pending;
  }

  /// The editable parts of a ride, as the `rides` table has them.
  static Map<String, dynamic> _details(PendingRide ride) => {
        'title': ride.title,
        'visibility': ride.visibility.dbValue,
        'journal': ride.journal,
        if (ride.startPlace != null) 'start_place': ride.startPlace,
        if (ride.endPlace != null) 'end_place': ride.endPlace,
      };

  Future<RideRecord> uploadPending(PendingRide pending) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw const AuthException('Not signed in');
    }
    if (pending.userId != null && pending.userId != uid) {
      // Recorded under another account; RLS would reject it. Wait for that rider.
      throw const AuthException('Ride belongs to a different account');
    }

    // Every ride is credited to a bike: the one picked by name, else primary.
    var bikeId = pending.bikeId;
    if (bikeId == null) {
      final bikes = await _bikes.listForUser(uid);
      bikeId = bikes.where((b) => b.name == pending.bikeName).firstOrNull?.id ??
          bikes.firstOrNull?.id; // listForUser puts the primary first
    }

    final row = {
      ..._details(pending),
      'bike_id': bikeId,
      'distance_km': pending.distanceKm,
      'moving_time_secs': pending.movingTimeSecs,
      'avg_speed_kmh': pending.avgSpeedKmh,
      'max_speed_kmh': pending.maxSpeedKmh,
      'elevation_m': pending.elevationM,
      'started_at': pending.startedAt?.toIso8601String(),
      'ended_at': pending.endedAt?.toIso8601String(),
      if (pending.cardImageUrl != null) 'card_image_url': pending.cardImageUrl,
    };
    if (pending.journal == null) row.remove('journal');

    // One round trip in the usual case: straight in. Only a ride that's
    // already there (a retry after a lost response, a ride resumed and
    // finished again, details changed offline) takes the long way.
    RideRecord ride;
    var trackNeeded = true;
    try {
      final insertRow = {...row, 'user_id': uid, 'local_id': pending.localId};
      logDbWrite('rides INSERT', insertRow);
      final inserted =
          await _client.from('rides').insert(insertRow).select().single();
      ride = RideRecord.fromJson(Map<String, dynamic>.from(inserted));
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
      final existing = RideRecord.fromJson(Map<String, dynamic>.from(
          await _client
              .from('rides')
              .select()
              .eq('user_id', uid)
              .eq('local_id', pending.localId)
              .single()));
      final updateRow = {...row, 'journal': pending.journal};
      logDbWrite('rides UPDATE id=${existing.id}', updateRow);
      final updated = await _client
          .from('rides')
          .update(updateRow)
          .eq('id', existing.id)
          .select()
          .single();
      ride = RideRecord.fromJson(Map<String, dynamic>.from(updated));
      // The same ride as before: its track only if it never made it.
      if ((existing.distanceKm - pending.distanceKm).abs() < 0.0005) {
        trackNeeded = await _client
                .from('ride_tracks')
                .select('id')
                .eq('ride_id', ride.id)
                .maybeSingle() ==
            null;
      }
    }

    if (trackNeeded && pending.points.isNotEmpty) {
      await _putTrack(ride.id, pending.points);
    }
    return ride;
  }

  /// Puts the uploaded ride [ride]'s ride card and photos up (those still
  /// on the phone), then tells whatever shows them. Network trouble leaves
  /// the rest for [RideSyncService].
  Future<void> _uploadExtras(PendingRide ride) async {
    try {
      final card = await uploadCard(ride);
      final media = await uploadMedia(ride);
      if (card) _changes.rides();
      if (media > 0) _changes.media();
    } catch (e) {
      debugPrint('Ride card/photos deferred: $e');
    }
  }

  /// Uploads the ride card kept on the phone for the uploaded [ride] and
  /// points the ride at it. True if it changed. A card the server refuses
  /// (too big, bucket missing…) is dropped so it can't be retried forever;
  /// network trouble throws, to try again later.
  Future<bool> uploadCard(PendingRide ride) async {
    final rideId = ride.remoteId;
    final uid = _client.auth.currentUser?.id;
    if (rideId == null || uid == null || !ride.hasCard) return false;
    final jpeg = await _store.loadCard(ride.localId);
    if (jpeg == null) return false;
    if (!_uploadingExtras.add('card:${ride.localId}')) return false;
    try {
      final path = _cardPath(uid, ride.localId);
      final bucket = _client.storage.from(cardBucket);
      String? url;
      try {
        logStorageUpload(cardBucket, path, jpeg, 'image/jpeg');
        await bucket.uploadBinary(
          path,
          jpeg,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            cacheControl: '31536000',
            upsert: true, // a new card replaces the old one
          ),
        );
        // A new address for a new card, so caches don't keep the old one.
        url =
            '${bucket.getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
        logDbWrite('rides UPDATE id=$rideId', {'card_image_url': url});
        await _client
            .from('rides')
            .update({'card_image_url': url}).eq('id', rideId);
      } on StorageException catch (e) {
        final status = int.tryParse(e.statusCode ?? '') ?? 0;
        if (status < 400 || status >= 500) rethrow;
        debugPrint('Ride card refused (${e.statusCode}): ${e.message}');
      }
      await _store.markCardUploaded(ride.localId, url);
      ride.cardImageUrl = url;
      return url != null;
    } finally {
      _uploadingExtras.remove('card:${ride.localId}');
    }
  }

  static String _cardPath(String uid, String localId) => '$uid/$localId.jpg';

  /// Posts [jpeg] as the ride card of the saved ride [ride], or takes its
  /// card off (null). Kept on the phone and uploaded when it can be.
  Future<PendingRide> setCard(PendingRide ride, Uint8List? jpeg) async {
    final uid = _client.auth.currentUser?.id;
    if (jpeg == null) {
      await _store.deleteCard(ride.localId);
      final stored = await _store.update(
          ride.localId, (r) => r.copyWith(hasCard: false)..cardImageUrl = null);
      final rideId = stored?.remoteId ?? ride.remoteId;
      if (rideId != null && uid != null) {
        try {
          await _client
              .from('rides')
              .update({'card_image_url': null}).eq('id', rideId);
          await _client.storage
              .from(cardBucket)
              .remove([_cardPath(uid, ride.localId)]);
        } catch (e) {
          debugPrint('Couldn\'t take the ride card off: $e');
        }
      }
      _changes.rides();
      return (stored ?? ride).copyWith(hasCard: false)..cardImageUrl = null;
    }
    await _store.saveCard(ride.localId, jpeg);
    final stored = await _store.update(
        ride.localId, (r) => r.copyWith(hasCard: true)..cardImageUrl = null);
    final saved = stored ?? ride.copyWith(hasCard: true);
    if (saved.synced) await _uploadExtras(saved);
    return saved;
  }

  /// Changes a ride saved from this phone: its title, words, bike, who can
  /// see it, place names and photos, as [edited] has them. On the phone
  /// first; the uploaded ride changes too (or does once it can).
  Future<PendingRide> updateSaved(PendingRide edited) async {
    final uid = _client.auth.currentUser?.id;
    final stored = await _store.find(edited.localId);
    if (stored == null) return edited;
    final uploadedMedia = {
      for (final m in stored.media)
        if (m.uploaded) m.id,
    };
    var next = edited.copyWith(
      synced: stored.synced,
      remoteId: stored.remoteId,
      hasCard: stored.hasCard,
      cardImageUrl: stored.cardImageUrl,
      media: [
        for (final m in edited.media)
          uploadedMedia.contains(m.id) ? m.markUploaded() : m,
      ],
    );
    final bikeChanged = next.bikeId != stored.bikeId;
    if (stored.synced && stored.remoteId != null && uid != null) {
      try {
        await _client
            .from('rides')
            .update({
              ..._details(next),
              if (next.bikeId != null) 'bike_id': next.bikeId,
            })
            .eq('id', stored.remoteId!)
            .eq('user_id', uid);
      } catch (e) {
        // Offline: it goes up with the next sync.
        debugPrint('Ride changes deferred: $e');
        next = next.copyWith(synced: false);
      }
    }
    await _store.update(next.localId, (_) => next);
    _changes.rides();
    if (bikeChanged) _changes.bikes();
    if (next.synced) unawaited(_uploadExtras(next));
    return next;
  }

  /// Takes [media] off the saved ride [ride]: out of its journal if it went
  /// up, and off the phone.
  Future<void> removeMedia(PendingRide ride, PendingMedia media) async {
    final uid = _client.auth.currentUser?.id;
    final stored = await _store.find(ride.localId);
    final uploaded =
        stored?.media.any((m) => m.id == media.id && m.uploaded) ?? false;
    final rideId = stored?.remoteId ?? ride.remoteId;
    if (uploaded && rideId != null && uid != null) {
      await _journal.deleteByPath('$uid/$rideId/${media.fileName}');
      _changes.media();
    }
    await _store.deleteMedia(ride.localId, media);
    await _store.update(
        ride.localId,
        (r) => r.copyWith(media: [
              for (final m in r.media)
                if (m.id != media.id) m
            ]));
  }

  /// Uploads the photos and videos kept on the phone for [ride] (uploaded,
  /// so it has a [PendingRide.remoteId]) into its journal, and returns how
  /// many went up. One the server refuses is dropped so it can't hold the
  /// rest back forever; network trouble throws, to try again later.
  Future<int> uploadMedia(PendingRide ride) async {
    final rideId = ride.remoteId;
    if (rideId == null) return 0;
    if (!_uploadingExtras.add('media:${ride.localId}')) {
      _mediaAgain.add(ride.localId); // picked up by the upload under way
      return 0;
    }
    var uploaded = 0;
    try {
      do {
        _mediaAgain.remove(ride.localId);
        uploaded += await _uploadMediaPass(ride, rideId);
      } while (_mediaAgain.contains(ride.localId));
    } finally {
      _uploadingExtras.remove('media:${ride.localId}');
    }
    return uploaded;
  }

  Future<int> _uploadMediaPass(PendingRide ride, String rideId) async {
    var uploaded = 0;
    // Up to date: photos added since this copy was read count too.
    final media = (await _store.find(ride.localId))?.media ?? ride.media;
    for (final m in media) {
      if (m.uploaded) continue;
      final bytes = await _store.loadMedia(ride.localId, m);
      if (bytes != null) {
        try {
          await _journal.addMedia(
            rideId: rideId,
            bytes: bytes,
            extension: m.extension,
            lat: m.lat,
            lng: m.lng,
            takenAt: m.takenAt,
            name: m.id,
          );
          uploaded++;
        } on StorageException catch (e) {
          final status = int.tryParse(e.statusCode ?? '') ?? 0;
          if (status < 400 || status >= 500) rethrow;
          debugPrint('Ride photo refused (${e.statusCode}): ${e.message}');
        } on PostgrestException catch (e) {
          if ((int.tryParse(e.code ?? '') ?? 0) >= 500) rethrow;
          debugPrint('Ride photo refused (${e.code}): ${e.message}');
        } on ArgumentError catch (e) {
          debugPrint('Ride photo skipped: $e');
        }
      }
      await _store.markMediaUploaded(ride.localId, m);
    }
    return uploaded;
  }

  /// Names the places an uploaded ride of the rider's set off from and
  /// reached (see [RideRecord.endPlace]).
  /// [title] renames it too (a ride still called what the app called it).
  Future<void> setPlaces(String rideId,
      {String? startPlace, String? endPlace, String? title}) async {
    if (startPlace == null && endPlace == null) return;
    await _client.from('rides').update({
      if (startPlace != null) 'start_place': startPlace,
      if (endPlace != null) 'end_place': endPlace,
      if (title != null) 'title': title,
    }).eq('id', rideId);
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

  /// The ride's track, replacing any it had (a resumed ride's is longer).
  Future<void> _putTrack(String rideId, List<TrackPoint> points) {
    final track = {'ride_id': rideId, 'points': encodeTrack(points)};
    logDbWrite('ride_tracks UPSERT (${points.length} points)', track);
    return _client.from('ride_tracks').upsert(track, onConflict: 'ride_id');
  }

  /// A ride in a list: the ride, its rider and bike, and its track's
  /// preview (see `20261018000000_track_previews.sql`), or the full track.
  static String _feedSelect({bool preview = true}) => '*, '
      'rider:profiles(id, username, display_name, avatar_url, city), '
      'bike:bikes(name, photo_url), '
      'track:ride_tracks(${preview ? 'preview' : 'points'})';

  /// The server has no track previews yet (the migration isn't applied):
  /// lists load full tracks instead.
  static bool _noPreviews = false;

  /// Tests: forget that the server had no previews.
  @visibleForTesting
  static void debugReset() => _noPreviews = false;

  /// Runs a list query for rides, with track previews when the server has
  /// them.
  Future<List> _listRides(Future<dynamic> Function(String select) query) async {
    if (!_noPreviews) {
      try {
        return await query(_feedSelect()) as List;
      } on PostgrestException catch (e) {
        final missing = e.code == '42703' || e.message.contains('preview');
        if (!missing) rethrow;
        debugPrint('No track previews on the server yet: ${e.message}');
        _noPreviews = true;
      }
    }
    return await query(_feedSelect(preview: false)) as List;
  }

  /// Rides the current viewer may see (RLS applies visibility), newest first.
  Future<List<FeedItem>> feed({int limit = 30}) async {
    final at = DateTime.now();
    final rows = await _listRides((select) => _client
        .from('rides')
        .select(select)
        .order('created_at', ascending: false)
        .limit(limit));
    return _toFeedItems(rows, at);
  }

  /// One feed ride by id (e.g. announced by Realtime), or null if this rider
  /// can't see it.
  Future<FeedItem?> feedItem(String id) async {
    final at = DateTime.now();
    final rows = await _listRides(
        (select) => _client.from('rides').select(select).eq('id', id).limit(1));
    final items = await _toFeedItems(rows, at);
    return items.firstOrNull;
  }

  /// Most-kudosed public rides of the last [days] days.
  Future<List<FeedItem>> popular({int days = 30, int limit = 20}) async {
    final at = DateTime.now();
    final since = at.toUtc().subtract(Duration(days: days));
    final rows = await _listRides((select) => _client
        .from('rides')
        .select(select)
        .eq('visibility', 'public')
        .gte('created_at', since.toIso8601String())
        .order('kudos_count', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit));
    return _toFeedItems(rows, at);
  }

  /// The signed-in rider's own rides, newest first, one page at a time.
  Future<List<FeedItem>> myRides({int offset = 0, int limit = 20}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    return ridesForUser(uid, offset: offset, limit: limit);
  }

  /// [userId]'s rides that this rider may see (RLS applies visibility),
  /// newest first, one page at a time.
  Future<List<FeedItem>> ridesForUser(String userId,
      {int offset = 0, int limit = 20}) async {
    final at = DateTime.now();
    final rows = await _listRides((select) => _client
        .from('rides')
        .select(select)
        .eq('user_id', userId)
        // Ride time, not upload time: offline rides can sync days later.
        .order('started_at', ascending: false, nullsFirst: false)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1));
    return _toFeedItems(rows, at);
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
              'max_speed_kmh, elevation_m, started_at, ended_at, created_at, '
              'local_id, end_place')
          .eq('user_id', uid)
          .order('created_at')
          .range(from, from + page - 1) as List;
      out.addAll(rows.map(
          (e) => RideRecord.fromJson(Map<String, dynamic>.from(e as Map))));
      if (rows.length < page) return out;
    }
  }

  /// The flags [userId]'s rides planted (see [flagPoint]), of the rides this
  /// rider may see, newest first.
  Future<List<RideFlag>> flagsForUser(String userId) async {
    const page = 1000; // PostgREST max_rows
    final out = <RideFlag>[];
    for (var from = 0;; from += page) {
      final rows = await _client
          .from('rides')
          .select('id, user_id, title, distance_km, started_at, ended_at, '
              'created_at, flag_lat, flag_lng, start_place, end_place, '
              'local_id')
          .eq('user_id', userId)
          .not('flag_lat', 'is', null)
          .order('started_at', ascending: false, nullsFirst: false)
          .range(from, from + page - 1) as List;
      out.addAll(rows
          .map((e) => RideFlag.fromJson(Map<String, dynamic>.from(e as Map)))
          .whereType<RideFlag>());
      if (rows.length < page) return out;
    }
  }

  /// Every rider's totals (of the rides this rider may see), most km
  /// first: see `rider_leaderboard()`.
  Future<List<RiderStanding>> leaderboard({int max = 100}) async {
    final rows = await _client
        .rpc('rider_leaderboard', params: {'max_riders': max}) as List;
    return [
      for (final r in rows)
        RiderStanding.fromJson(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Rides saved on this device for the signed-in rider that haven't synced.
  Future<List<PendingRide>> myPendingRides() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    final pending = await _store.pendingUnsynced();
    return pending.where((r) => r.userId == null || r.userId == uid).toList();
  }

  /// [at] is when the rows were requested (see [FeedItem.fetchedAt]).
  Future<List<FeedItem>> _toFeedItems(List rows, DateTime at) async {
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
      return FeedItem.fromJson(json,
          likedByMe: liked.contains(json['id']), fetchedAt: at);
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
    return decodeTrack(row['points']);
  }

  /// Changes who can see one of the rider's rides: the uploaded ride (by
  /// [rideId], else by [localId]) and its copy on this phone, so one still
  /// waiting to upload goes up that way. Throws if an uploaded ride can't be
  /// changed (offline).
  Future<void> setVisibility(RideVisibility visibility,
      {String? rideId, String? localId}) async {
    assert(rideId != null || localId != null);
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Not signed in');
    final stored = localId == null
        ? null
        : await _store.setVisibility(localId, visibility);
    try {
      final update = _client
          .from('rides')
          .update({'visibility': visibility.dbValue}).eq('user_id', uid);
      await (rideId != null
          ? update.eq('id', rideId)
          : update.eq('local_id', localId!));
    } catch (_) {
      // Offline. Fine if it's only on this phone: it uploads as changed.
      if (rideId != null || stored == null || stored.synced) rethrow;
    }
    _changes.rides();
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
    if (ride.hasCard) {
      try {
        await _client.storage
            .from(cardBucket)
            .remove([_cardPath(uid, ride.localId)]);
      } catch (_) {
        // An orphaned image is harmless; the ride is already gone.
      }
    }
    if (ride.remoteId != null) {
      await _journal.removeAllFor(ride.remoteId!);
      _changes.rideDeleted(ride.remoteId!);
    }
    _changes.rides();
    _changes.bikes();
  }

  Future<void> deleteRide(String rideId) async {
    await _client.from('rides').delete().eq('id', rideId);
    await _journal.removeAllFor(rideId);
    _changes.rideDeleted(rideId);
    _changes.rides();
    _changes.bikes();
  }
}
