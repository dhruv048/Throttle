import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'core.dart';
import 'live.dart';

/// The signed-in rider's profile: null when signed out, or if it couldn't be
/// found.
final myProfileProvider =
    AsyncNotifierProvider<MyProfile, Profile?>(MyProfile.new);

class MyProfile extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return null;
    final profiles = ref.watch(profileRepositoryProvider);
    // A new account's profile row is made by a trigger just after sign-up.
    for (var i = 0;; i++) {
      final profile = await profiles.getById(uid);
      if (profile != null || i == 7) return profile;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!ref.mounted) return null;
    }
  }

  /// The profile as onboarding saved it.
  void set(Profile profile) => state = AsyncData(profile);
}

/// The signed-in rider's bikes, primary first. Rides still on this phone
/// count toward their bike's km straight away; the server credits them once
/// they upload.
final myBikesProvider = FutureProvider<List<BikeRecord>>((ref) async {
  ref.watch(bikesRevisionProvider);
  ref.watch(ridesRevisionProvider);
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const [];
  final (bikes, pending) = await (
    ref.watch(bikeRepositoryProvider).listForUser(uid),
    ref
        .watch(rideRepositoryProvider)
        .myPendingRides()
        .catchError((Object _) => const <PendingRide>[]),
  ).wait;
  return withRidesOnPhone(bikes, pending);
});

/// [bikes] with the km of [pending] rides (not uploaded yet) added to the
/// bike each was ridden on (the primary if none was picked).
List<BikeRecord> withRidesOnPhone(
    List<BikeRecord> bikes, List<PendingRide> pending) {
  if (bikes.isEmpty || pending.isEmpty) return bikes;
  final primary = bikes.first.id; // listForUser puts it first
  final extra = <String, double>{};
  for (final r in pending) {
    final id = bikes.any((b) => b.id == r.bikeId)
        ? r.bikeId!
        : bikes.where((b) => b.name == r.bikeName).firstOrNull?.id ?? primary;
    extra[id] = (extra[id] ?? 0) + r.distanceKm;
  }
  return [
    for (final b in bikes)
      extra[b.id] == null ? b : b.copyWith(riddenKm: b.riddenKm + extra[b.id]!),
  ];
}

/// How many riders follow the signed-in rider, and how many they follow.
final myFollowCountsProvider =
    FutureProvider<({int followers, int following})>((ref) async {
  ref.watch(followsRevisionProvider);
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return (followers: 0, following: 0);
  return ref.watch(profileRepositoryProvider).followCounts(uid);
});

/// Ids of the riders the signed-in rider follows.
final followingProvider =
    AsyncNotifierProvider<Following, Set<String>>(Following.new);

class Following extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    ref.watch(followsRevisionProvider);
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const {};
    return ref.watch(profileRepositoryProvider).followingIds(uid);
  }

  /// Follows [riderId], or unfollows if already following. Shown right
  /// away; put back (and rethrown) if it doesn't go through.
  Future<void> toggle(String riderId) async {
    final uid = ref.read(currentUserIdProvider);
    final before = state.value;
    if (uid == null || before == null) return;
    final wasFollowing = before.contains(riderId);
    state = AsyncData(
        wasFollowing ? ({...before}..remove(riderId)) : {...before, riderId});
    try {
      final profiles = ref.read(profileRepositoryProvider);
      wasFollowing
          ? await profiles.unfollow(uid, riderId)
          : await profiles.follow(uid, riderId);
    } catch (_) {
      if (ref.mounted) state = AsyncData(before);
      rethrow;
    }
  }
}

/// Riders matching a search by username or name (all riders when it's
/// empty), newest first, without the signed-in rider.
final riderSearchProvider =
    FutureProvider.autoDispose.family<List<Profile>, String>((ref, query) {
  final uid = ref.watch(currentUserIdProvider);
  return ref.watch(profileRepositoryProvider).search(query, excludeId: uid);
});

// Any rider's profile page. Each loads when the page opens and is dropped
// when it closes.

/// A rider's profile; null if there's no such rider.
final riderProfileProvider =
    FutureProvider.autoDispose.family<Profile?, String>((ref, riderId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(profileRepositoryProvider).getById(riderId);
});

/// How many riders follow a rider, and how many they follow.
final riderFollowCountsProvider = FutureProvider.autoDispose
    .family<({int followers, int following}), String>((ref, riderId) {
  ref.watch(followsRevisionProvider);
  return ref.watch(profileRepositoryProvider).followCounts(riderId);
});

/// A rider's bikes, primary first.
final riderBikesProvider =
    FutureProvider.autoDispose.family<List<BikeRecord>, String>((ref, riderId) {
  ref.watch(bikesRevisionProvider);
  return ref.watch(bikeRepositoryProvider).listForUser(riderId);
});

/// A rider's photos and videos loaded so far, newest first.
@immutable
class MediaPages {
  const MediaPages(this.items,
      {required this.hasMore, this.loadingMore = false});

  final List<RideMedia> items;
  final bool hasMore;
  final bool loadingMore;
}

/// A rider's memories: the photos and videos from their rides that the
/// signed-in rider may see, newest first, a page at a time.
final riderMemoriesProvider = AsyncNotifierProvider.autoDispose
    .family<RiderMemories, MediaPages, String>(RiderMemories.new);

class RiderMemories extends AsyncNotifier<MediaPages> {
  RiderMemories(this.riderId);

  final String riderId;
  static const pageSize = 60;

  @override
  Future<MediaPages> build() async {
    ref.watch(currentUserIdProvider);
    ref.watch(ridesRevisionProvider);
    ref.watch(followsRevisionProvider);
    ref.watch(mediaRevisionProvider);
    final page = await ref
        .watch(journalRepositoryProvider)
        .riderMedia(riderId, limit: pageSize);
    return MediaPages(page, hasMore: page.length == pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (state.isLoading ||
        current == null ||
        !current.hasMore ||
        current.loadingMore) {
      return;
    }
    final loading = MediaPages(current.items, hasMore: true, loadingMore: true);
    state = AsyncData(loading);
    try {
      final page = await ref
          .read(journalRepositoryProvider)
          .riderMedia(riderId, offset: current.items.length, limit: pageSize);
      if (!ref.mounted || !identical(state.value, loading)) return;
      state = AsyncData(MediaPages([...current.items, ...page],
          hasMore: page.length == pageSize));
    } catch (_) {
      if (ref.mounted && identical(state.value, loading)) {
        state = AsyncData(current);
      }
    }
  }
}

/// The flags a rider's rides planted, of the rides the signed-in rider may
/// see, newest first.
final riderFlagsProvider =
    FutureProvider.autoDispose.family<List<RideFlag>, String>((ref, riderId) {
  ref.watch(currentUserIdProvider);
  ref.watch(ridesRevisionProvider);
  ref.watch(followsRevisionProvider);
  return ref.watch(rideRepositoryProvider).flagsForUser(riderId);
});
