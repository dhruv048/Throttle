import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../repositories/ride_repository.dart';
import 'local_ride_store.dart';
import 'ride_events.dart';

class RideSyncService {
  RideSyncService({
    LocalRideStore? store,
    RideRepository? rides,
    Connectivity? connectivity,
  })  : _store = store ?? LocalRideStore(),
        _rides = rides ?? RideRepository(),
        _connectivity = connectivity ?? Connectivity();

  final LocalRideStore _store;
  final RideRepository _rides;
  final Connectivity _connectivity;
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

  void dispose() {
    _sub?.cancel();
  }

  Future<int> syncPending() async {
    if (_syncing) return 0;
    _syncing = true;
    var synced = 0;
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
    } finally {
      _syncing = false;
    }
    if (synced > 0) RideEvents.notify();
    return synced;
  }
}
