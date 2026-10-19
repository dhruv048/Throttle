import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Refreshable;

import 'core.dart';

/// The Shell's tabs, in bottom-nav order.
enum AppTab { home, discover, record, activity, profile }

/// The tab on screen. Every tab stays alive in the Shell; this says which
/// one is visible, so it refreshes when shown, and Record only uses GPS
/// while it's on screen.
final currentTabProvider = NotifierProvider<CurrentTab, AppTab>(CurrentTab.new);

class CurrentTab extends Notifier<AppTab> {
  @override
  AppTab build() {
    ref.watch(currentUserIdProvider); // each rider starts on Home
    return AppTab.home;
  }

  void show(AppTab tab) => state = tab;
}

/// Reloads [providers], completing once all have finished, loaded or not
/// (for pull-to-refresh). Each keeps showing its data until the new data
/// arrives.
Future<void> refreshAll(
  WidgetRef ref,
  List<Refreshable<Future<Object?>>> providers,
) =>
    Future.wait([
      for (final provider in providers)
        ref.refresh(provider).then<void>((_) {}, onError: (_) {}),
    ]);
