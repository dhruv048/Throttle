import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throttle/providers/live.dart';
import 'package:throttle/screens/home_screen.dart';
import 'package:throttle/screens/notifications_screen.dart';
import 'package:throttle/screens/ride_detail_screen.dart';
import 'package:throttle/services/local_ride_store.dart';
import 'package:throttle/widgets/map_tiles.dart';

import 'support/fake_gps.dart';
import 'support/fake_supabase.dart';
import 'support/providers.dart';

late FakeSupabase backend;

Future<void> _arrive(WidgetTester tester) async {
  backend.release();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets a page animate in or out.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(withProviders(const MaterialApp(home: HomeScreen())));
  await _arrive(tester);
  // Home's Start Ride card rises in after 2 s.
  await tester.pump(const Duration(seconds: 3));
}

/// The unread count on the bell.
Finder _badge([String? count]) => find.descendant(
    of: find.byKey(const ValueKey('unread-badge')),
    matching: count == null ? find.byType(Text) : find.text(count));

void main() {
  setUpAll(() async {
    backend = await FakeSupabase.start(userId: 'me');
    MapTiles.debugProvider = BlankTiles();
  });

  setUp(() {
    LocalRideStore.debugReset();
    backend.reset();
    backend.tables
      ..['profiles'] = [
        Fixtures.profile(),
        Fixtures.profile(
            id: 'mira', username: 'mira_rai', displayName: 'Mira Rai'),
        Fixtures.profile(
            id: 'arjun', username: 'arjun_t', displayName: 'Arjun Thapa'),
      ]
      ..['bikes'] = [Fixtures.bike()]
      ..['rides'] = [Fixtures.ride()]
      ..['follows'] = []
      ..['kudos'] = []
      ..['notifications'] = [
        Fixtures.notification(id: 'n1'),
        Fixtures.notification(
            id: 'n2',
            kind: 'follow',
            actorId: 'arjun',
            actorName: 'Arjun Thapa'),
        Fixtures.notification(
            id: 'n3', read: true, ago: const Duration(days: 3)),
      ];
  });

  testWidgets('the bell shows how many are new; opening them marks them read',
      (tester) async {
    await _pumpHome(tester);
    expect(_badge('2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.notifications));
    await _arrive(tester);
    await _settle(tester);

    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.text('NEW'), findsOneWidget);
    expect(find.text('EARLIER'), findsOneWidget);
    expect(
        find.text('Mira Rai gave kudos on Nagarkot sunrise run',
            findRichText: true),
        findsNWidgets(2)); // a new one, and one read earlier
    expect(find.text('Arjun Thapa started following you', findRichText: true),
        findsOneWidget);
    expect(find.text('Follow back'), findsOneWidget);

    // All read on the server, but still marked new while it's open.
    expect(backend.tables['notifications']!.every((n) => n['read_at'] != null),
        isTrue);
    expect(find.text('NEW'), findsOneWidget);

    await tester.pageBack();
    await _arrive(tester);
    await _settle(tester);
    expect(_badge(), findsNothing);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
  });

  testWidgets('follow back from a new follower', (tester) async {
    await tester.pumpWidget(
        withProviders(const MaterialApp(home: NotificationsScreen())));
    await _arrive(tester);
    await tester.tap(find.text('Follow back'));
    await _arrive(tester);
    expect(backend.tables['follows'], [
      {'follower_id': 'me', 'following_id': 'arjun'},
    ]);
    expect(find.text('Following'), findsOneWidget);
  });

  testWidgets('kudos opens the ride', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        withProviders(const MaterialApp(home: NotificationsScreen())));
    await _arrive(tester);
    await tester.tap(find
        .text('Mira Rai gave kudos on Nagarkot sunrise run', findRichText: true)
        .first);
    await _arrive(tester);
    await _settle(tester);
    expect(find.byType(RideDetailScreen), findsOneWidget);
  });

  testWidgets('a new one arriving live updates the bell', (tester) async {
    backend.tables['notifications'] = [];
    await _pumpHome(tester);
    expect(_badge(), findsNothing);

    backend.tables['notifications']!.add(Fixtures.notification(id: 'n9'));
    // What Realtime reports when the row is inserted.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    container.read(dataChangesProvider).notifications();
    await _arrive(tester);
    expect(_badge('1'), findsOneWidget);
  });
}
