/// A ride's live counters changed, from a kudos tap here or from the server.
class RideUpdate {
  const RideUpdate({
    required this.id,
    this.kudosCount,
    this.commentsCount,
    this.likedByMe,
  });

  final String id;
  final int? kudosCount;
  final int? commentsCount;

  /// Only known for this rider's own kudos taps.
  final bool? likedByMe;
}

/// Where the data layer reports what it changed: this app's own writes
/// (repositories, `RideSyncService`) and, through `RealtimeService`, changes
/// made anywhere else.
///
/// The app passes in an implementation that refreshes whatever shows that
/// data (see `lib/providers/live.dart`); this default ignores everything.
class DataChanges {
  const DataChanges();

  /// The signed-in rider's rides were added, synced, edited or deleted.
  void rides() {}

  /// The rider's bikes changed (added, edited, new photo, km ridden).
  void bikes() {}

  /// Who the rider follows, or who follows them, changed.
  void follows() {}

  /// A ride just became visible to this rider (anyone's).
  void rideAdded(String id) {}

  /// A ride's kudos or comment counts changed.
  void rideUpdated(RideUpdate update) {}

  /// A ride was deleted, anywhere.
  void rideDeleted(String id) {}

  /// The rider's notifications changed (a new one, or read).
  void notifications() {}

  /// Photos or videos were added to (or removed from) a ride's journal.
  void media() {}
}
