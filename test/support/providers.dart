import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:throttle/providers/core.dart';
import 'package:throttle/providers/navigation.dart';
import 'package:throttle/services/place_names.dart';

import 'fake_places.dart';

/// [child] with the app's providers, set up like `main` does. [tab] is the
/// Shell tab on screen: Record only uses GPS while it's showing. Use
/// `tester.container()` to reach the providers. Places are named by
/// [places] (none, by default), never over the network.
Widget withProviders(Widget child,
        {AppTab tab = AppTab.home,
        List<Override> overrides = const [],
        PlaceNames? places}) =>
    ProviderScope(
      retry: noRetry,
      overrides: [
        if (tab != AppTab.home)
          currentTabProvider.overrideWithBuild((ref, notifier) => tab),
        placeNamesProvider.overrideWithValue(places ?? FakePlaceNames()),
        ...overrides,
      ],
      child: child,
    );
