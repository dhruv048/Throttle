import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../repositories/ride_repository.dart';
import 'data_changes.dart';
import 'local_ride_store.dart';

class RideSyncService {
  RideSyncService({
    LocalRideStore? store,
    RideRepository? rides,
    Connectivity? connectivity,
    DataChanges changes = const DataChanges(),
  })  : _store = store ?? LocalRideStore(),
        _rides = rides ?? RideRepository(),
        _connectivity = connectivity ?? Connectivity(),
        _changes = changes;

  final LocalRideStore _store;
  final RideRepository _rides;
  final Connectivity _connectivity;
  final DataChanges _changes;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _syncing = false;

  void start() {
    _sub?.cancel();
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(syncPending());
      }
    });
    unawaited(syncPending());
  }

  /// Stops syncing when the connection comes back.
  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<int> syncPending() async {
    if (_syncing) return 0;
    _syncing = true;
    var synced = 0;
    var extras = false;
    var media = 0;
    try {
      final pending = await _store.pendingUnsynced();
      for (final ride in pending) {
        try {
          final remote = await _rides.uploadPending(ride);
          await _store.markSynced(ride.localId, remote.id);
          synced += 1;
        } catch (e, st) {
          debugPrint('Ride sync failed for ${ride.localId}: $e\n$st');
        }
      }
      // Ride cards, photos and videos still to go up with rides that have.
      for (final ride in await _store.withUploadsLeft()) {
        try {
          extras = await _rides.uploadCard(ride) || extras;
          media += await _rides.uploadMedia(ride);
        } catch (e) {
          debugPrint('Ride card/photos sync failed for ${ride.localId}: $e');
        }
      }
    } finally {
      _syncing = false;
    }
    if (synced > 0 || extras) _changes.rides();
    if (synced > 0) _changes.bikes(); // the server credited each bike's km
    if (media > 0) _changes.media();
    return synced;
  }
}
