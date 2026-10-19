import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/achievements.dart';
import 'core.dart';
import 'live.dart';

/// Rides the signed-in rider may see, newest first: the Home feed. Rides
/// shared while it's open are added to the top as Realtime announces them.
final homeFeedProvider =
    AsyncNotifierProvider<HomeFeed, List<FeedItem>>(HomeFeed.new);

class HomeFeed extends AsyncNotifier<List<FeedItem>> {
  static const limit = 30;

  @override
  Future<List<FeedItem>> build() {
    ref.watch(currentUserIdProvider);
    ref.watch(ridesRevisionProvider);
    ref.watch(followsRevisionProvider);
    return ref.watch(rideRepositoryProvider).feed(limit: limit);
  }

  /// A ride someone just shared: add it to the top.
  Future<void> rideAdded(String id) async {
    if (state.value?.any((f) => f.ride.id == id) ?? true) return;
    // The GPS track is written just after the ride row; give it a moment.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    var item = await _fetch(id);
    if (item == null || !_insert(item)) return;
    if (item.points.isEmpty) {
      await Future<void>.delayed(const Duration(seconds: 4));
      item = await _fetch(id);
      if (item != null && item.points.isNotEmpty) _replace(item);
    }
  }

  Future<FeedItem?> _fetch(String id) async {
    if (!ref.mounted) return null;
    try {
      return await ref.read(rideRepositoryProvider).feedItem(id);
    } catch (_) {
      return null;
    }
  }

  bool _insert(FeedItem item) {
    final feed = state.value;
    if (!ref.mounted ||
        feed == null ||
        feed.any((f) => f.ride.id == item.ride.id)) {
      return false;
    }
    state = AsyncData([item, ...feed].take(limit).toList());
    return true;
  }

  void _replace(FeedItem item) {
    final feed = state.value;
    if (!ref.mounted || feed == null) return;
    state =
        AsyncData([for (final f in feed) f.ride.id == item.ride.id ? item : f]);
  }
}

/// The most-kudosed public rides of the last 30 days, for Discover.
final popularRidesProvider = FutureProvider<List<FeedItem>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(rideRepositoryProvider).popular();
});

/// Rides saved on this phone for the signed-in rider that haven't uploaded.
/// Always available, even offline.
final myPendingRidesProvider = FutureProvider<List<PendingRide>>((ref) {
  ref.watch(currentUserIdProvider);
  ref.watch(ridesRevisionProvider);
  return ref.watch(rideRepositoryProvider).myPendingRides();
});

/// Every ride the signed-in rider has uploaded (lightweight rows), for
/// totals.
final myRideHistoryProvider = FutureProvider<List<RideRecord>>((ref) {
  ref.watch(currentUserIdProvider);
  ref.watch(ridesRevisionProvider);
  return ref.watch(rideRepositoryProvider).myRideHistory();
});

/// How many rides the signed-in rider has uploaded.
final myRideCountProvider = FutureProvider<int>((ref) async {
  ref.watch(ridesRevisionProvider);
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return 0;
  return ref.watch(rideRepositoryProvider).countForUser(uid);
});

/// The rider's uploaded rides loaded so far, newest first.
@immutable
class RidePages {
  const RidePages(this.items,
      {required this.hasMore, this.loadingMore = false});

  final List<FeedItem> items;
  final bool hasMore;
  final bool loadingMore;
}

/// The signed-in rider's own uploaded rides, newest first, a page at a time.
final myRidesProvider = AsyncNotifierProvider<MyRides, RidePages>(MyRides.new);

class MyRides extends AsyncNotifier<RidePages> {
  static const pageSize = 20;

  @override
  Future<RidePages> build() async {
    ref.watch(currentUserIdProvider);
    ref.watch(ridesRevisionProvider);
    final page =
        await ref.watch(rideRepositoryProvider).myRides(limit: pageSize);
    return RidePages(page, hasMore: page.length == pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (state.isLoading ||
        current == null ||
        !current.hasMore ||
        current.loadingMore) {
      return;
    }
    final loading = RidePages(current.items, hasMore: true, loadingMore: true);
    state = AsyncData(loading);
    try {
      final page = await ref
          .read(rideRepositoryProvider)
          .myRides(offset: current.items.length, limit: pageSize);
      // Reloaded meanwhile: this page belongs to the old list.
      if (!ref.mounted || !identical(state.value, loading)) return;
      state = AsyncData(RidePages([...current.items, ...page],
          hasMore: page.length == pageSize));
    } catch (_) {
      // Keep what we have; "Load more" stays for a retry.
      if (ref.mounted && identical(state.value, loading)) {
        state = AsyncData(current);
      }
    }
  }
}

/// A rider's rides that the signed-in rider may see, newest first, a page at
/// a time: more show once they follow the rider (followers-only rides).
final riderRidesProvider = AsyncNotifierProvider.autoDispose
    .family<RiderRides, RidePages, String>(RiderRides.new);

class RiderRides extends AsyncNotifier<RidePages> {
  RiderRides(this.riderId);

  final String riderId;
  static const pageSize = 20;

  @override
  Future<RidePages> build() async {
    ref.watch(currentUserIdProvider);
    ref.watch(ridesRevisionProvider);
    ref.watch(followsRevisionProvider);
    final page = await ref
        .watch(rideRepositoryProvider)
        .ridesForUser(riderId, limit: pageSize);
    return RidePages(page, hasMore: page.length == pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (state.isLoading ||
        current == null ||
        !current.hasMore ||
        current.loadingMore) {
      return;
    }
    final loading = RidePages(current.items, hasMore: true, loadingMore: true);
    state = AsyncData(loading);
    try {
      final page = await ref
          .read(rideRepositoryProvider)
          .ridesForUser(riderId, offset: current.items.length, limit: pageSize);
      if (!ref.mounted || !identical(state.value, loading)) return;
      state = AsyncData(RidePages([...current.items, ...page],
          hasMore: page.length == pageSize));
    } catch (_) {
      if (ref.mounted && identical(state.value, loading)) {
        state = AsyncData(current);
      }
    }
  }
}

/// How many of a rider's rides the signed-in rider may see.
final riderRideCountProvider =
    FutureProvider.autoDispose.family<int, String>((ref, riderId) {
  ref.watch(currentUserIdProvider);
  ref.watch(ridesRevisionProvider);
  ref.watch(followsRevisionProvider);
  return ref.watch(rideRepositoryProvider).countForUser(riderId);
});

/// An uploaded ride's full GPS track (lists only load a preview of it).
final rideTrackProvider =
    FutureProvider.autoDispose.family<List<TrackPoint>, String>((ref, rideId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(rideRepositoryProvider).trackForRide(rideId);
});

/// Riders and what they've achieved (totals of the rides this rider may
/// see), for Discover.
final leaderboardProvider = FutureProvider<List<RiderStanding>>((ref) {
  ref.watch(currentUserIdProvider);
  ref.watch(ridesRevisionProvider);
  ref.watch(followsRevisionProvider);
  return ref.watch(rideRepositoryProvider).leaderboard();
});
