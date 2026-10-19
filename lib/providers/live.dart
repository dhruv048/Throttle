import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/data_changes.dart';
import 'core.dart';
import 'rides.dart';

// How changes reach the screens: this app's own writes and Realtime both
// report them through [DataChanges]; [AppDataChanges] turns each into
// provider updates. Data providers watch a [Revision] to reload, while
// per-ride changes (counts, deletions) are patched in without reloading.

/// Counts changes to one kind of the rider's data, made by this app or (via
/// Realtime) anywhere else. Providers that load that data watch it, so each
/// change reloads them.
class Revision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// The signed-in rider's own rides (saved, synced, deleted).
final ridesRevisionProvider = NotifierProvider<Revision, int>(Revision.new);

/// The rider's bikes (added, edited, new photo, km ridden).
final bikesRevisionProvider = NotifierProvider<Revision, int>(Revision.new);

/// Who the rider follows, or who follows them.
final followsRevisionProvider = NotifierProvider<Revision, int>(Revision.new);

/// The rider's notifications (a new one arrived, or they were read).
final notificationsRevisionProvider =
    NotifierProvider<Revision, int>(Revision.new);

/// Photos and videos in the rider's ride journals (e.g. ones that finished
/// uploading after their ride).
final mediaRevisionProvider = NotifierProvider<Revision, int>(Revision.new);

/// Ids of rides deleted (anywhere) since the rider signed in, so lists that
/// loaded earlier stop showing them.
final deletedRidesProvider =
    NotifierProvider<DeletedRides, Set<String>>(DeletedRides.new);

class DeletedRides extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(currentUserIdProvider);
    return const {};
  }

  void add(String id) {
    if (!state.contains(id)) state = {...state, id};
  }
}

typedef Stamped<T> = ({T value, DateTime at});

/// The newest kudos/comment counts known for a ride, from this rider's taps
/// and from Realtime, each with when it was learnt.
@immutable
class RideCounters {
  const RideCounters({this.kudos, this.comments, this.liked});

  final Stamped<int>? kudos;
  final Stamped<int>? comments;
  final Stamped<bool>? liked;

  RideCounters merge(RideUpdate update, DateTime at) => RideCounters(
        kudos: update.kudosCount == null
            ? kudos
            : (value: update.kudosCount!, at: at),
        comments: update.commentsCount == null
            ? comments
            : (value: update.commentsCount!, at: at),
        liked: update.likedByMe == null
            ? liked
            : (value: update.likedByMe!, at: at),
      );

  /// [item], with the counts that are newer than the data it was loaded
  /// with. Older ones are stale: a reload since then has the real numbers.
  FeedItem applyTo(FeedItem item) {
    final since = item.fetchedAt;
    T? newer<T>(Stamped<T>? c) =>
        c != null && (since == null || c.at.isAfter(since)) ? c.value : null;
    final kudosCount = newer(kudos);
    final commentsCount = newer(comments);
    final likedByMe = newer(liked);
    if (kudosCount == null && commentsCount == null && likedByMe == null) {
      return item;
    }
    return item.copyWith(
      kudosCount: kudosCount,
      commentsCount: commentsCount,
      likedByMe: likedByMe,
    );
  }
}

/// Live kudos/comment counts by ride id. The same ride can be on several
/// screens at once; cards overlay these on the item they were given (see
/// [watchLiveRide]), so they all stay in step.
final rideCountersProvider =
    NotifierProvider<RideCountersNotifier, Map<String, RideCounters>>(
        RideCountersNotifier.new);

class RideCountersNotifier extends Notifier<Map<String, RideCounters>> {
  /// Realtime reports changes to every ride the rider can see. Keep the most
  /// recently changed ones: plenty for what's on screen.
  static const keep = 500;

  final _busy = <String>{};

  @override
  Map<String, RideCounters> build() {
    ref.watch(currentUserIdProvider);
    _busy.clear();
    return const {};
  }

  void apply(RideUpdate update) {
    final counters = (state[update.id] ?? const RideCounters())
        .merge(update, DateTime.now());
    // Most recently changed last.
    final next = {...state}..remove(update.id);
    next[update.id] = counters;
    while (next.length > keep) {
      next.remove(next.keys.first);
    }
    state = next;
  }

  /// Gives (or takes back) this rider's kudos on [item], as it's currently
  /// shown. Every card shows it at once; it's undone if the server refuses.
  Future<void> toggleKudos(FeedItem item) async {
    final id = item.ride.id;
    if (item.pending || !_busy.add(id)) return;
    final before = state[id];
    final liked = !item.likedByMe;
    apply(RideUpdate(
      id: id,
      likedByMe: liked,
      kudosCount: item.ride.kudosCount + (liked ? 1 : -1),
    ));
    try {
      final rides = ref.read(rideRepositoryProvider);
      liked ? await rides.giveKudos(id) : await rides.removeKudos(id);
    } catch (_) {
      if (ref.mounted) {
        final undone = {...state}..remove(id);
        if (before != null) undone[id] = before;
        state = undone;
      }
    } finally {
      _busy.remove(id);
    }
  }
}

/// [item] with its newest known kudos/comment counts; rebuilds the widget
/// when they change.
FeedItem watchLiveRide(WidgetRef ref, FeedItem item) {
  final counters =
      ref.watch(rideCountersProvider.select((all) => all[item.ride.id]));
  return counters?.applyTo(item) ?? item;
}

/// [DataChanges] for the running app: reloads or patches whatever shows the
/// changed data.
final dataChangesProvider = Provider<DataChanges>(AppDataChanges.new);

class AppDataChanges extends DataChanges {
  AppDataChanges(this._ref);

  final Ref _ref;

  /// Changes come from outside the provider graph (finished uploads,
  /// Realtime), so they're applied to the container itself. Going through
  /// [_ref] would look like a cycle: the providers they reach load through
  /// repositories that report here.
  ProviderContainer get _app => _ref.container;

  @override
  void rides() =>
      _apply(() => _app.read(ridesRevisionProvider.notifier).bump());

  @override
  void bikes() =>
      _apply(() => _app.read(bikesRevisionProvider.notifier).bump());

  @override
  void follows() =>
      _apply(() => _app.read(followsRevisionProvider.notifier).bump());

  @override
  void notifications() =>
      _apply(() => _app.read(notificationsRevisionProvider.notifier).bump());

  @override
  void media() =>
      _apply(() => _app.read(mediaRevisionProvider.notifier).bump());

  @override
  void rideAdded(String id) => _apply(() {
        // Only the Home feed lists everyone's rides, newest first. If it
        // isn't loaded, it'll include this ride when it is.
        if (_app.exists(homeFeedProvider)) {
          unawaited(_app.read(homeFeedProvider.notifier).rideAdded(id));
        }
      });

  @override
  void rideUpdated(RideUpdate update) =>
      _apply(() => _app.read(rideCountersProvider.notifier).apply(update));

  @override
  void rideDeleted(String id) => _apply(() {
        _app.read(deletedRidesProvider.notifier).add(id);
        // One of the rider's own (e.g. deleted on another device): their
        // totals and lists reload too.
        if (_isOwnRide(id)) rides();
      });

  bool _isOwnRide(String id) {
    final history = _app.exists(myRideHistoryProvider)
        ? _app.read(myRideHistoryProvider).value
        : null;
    final pages =
        _app.exists(myRidesProvider) ? _app.read(myRidesProvider).value : null;
    return (history?.any((r) => r.id == id) ?? false) ||
        (pages?.items.any((f) => f.ride.id == id) ?? false);
  }

  /// Uploads can finish after the app (or a test) has torn its providers
  /// down; there's nothing left to update then.
  void _apply(void Function() change) {
    if (_ref.mounted) change();
  }
}

/// While a rider is signed in, rides saved on this phone keep uploading:
/// right away, and whenever the connection comes back.
final rideSyncProvider = Provider<void>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return;
  final sync = ref.watch(rideSyncServiceProvider);
  sync.start();
  ref.onDispose(sync.stop);
});

/// While a rider is signed in, database changes made anywhere (other riders,
/// other devices, server triggers) stream in through Supabase Realtime.
final realtimeProvider = Provider<void>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return;
  final realtime = ref.watch(realtimeServiceProvider);
  realtime.start(uid);
  ref.onDispose(realtime.stop);
});
