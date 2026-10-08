import 'package:flutter/foundation.dart';

/// Bumped whenever the rider's rides change (shared, synced, deleted) so the
/// screens kept alive in the bottom-nav IndexedStack can reload.
class RideEvents {
  RideEvents._();

  static final changed = ValueNotifier<int>(0);

  static void notify() => changed.value++;
}
