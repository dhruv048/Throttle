import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throttle/models/models.dart';
import 'package:throttle/screens/discover_screen.dart';
import 'package:throttle/screens/ride_detail_screen.dart';
import 'package:throttle/screens/rider_profile_screen.dart';
import 'package:throttle/services/local_ride_store.dart';
import 'package:throttle/widgets/map_tiles.dart';
import 'package:throttle/widgets/media_viewer.dart';
import 'package:throttle/widgets/ride_flag.dart';

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

/// Lets a page or sheet animate in or out.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(withProviders(MaterialApp(home: screen)));
  await _arrive(tester);
}

Map<String, dynamic> _miraRide(String id, {String visibility = 'public'}) =>
    Fixtures.ride(
        id: id, userId: 'mira', title: 'Mira ride $id', visibility: visibility)
      ..['rider'] = Fixtures.profile(
          id: 'mira', username: 'mira_rai', displayName: 'Mira Rai');

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
        {
          ...Fixtures.profile(
              id: 'mira',
              username: 'mira_rai',
              displayName: 'Mira Rai',
              city: 'Pokhara'),
          'bio': 'Weekend twisties, weekday commutes.',
        },
      ]
      ..['bikes'] = [
        Fixtures.bike(),
        Fixtures.bike(
            id: 'm1', userId: 'mira', name: 'Himalayan 450', riddenKm: 1200),
        Fixtures.bike(
            id: 'm2',
            userId: 'mira',
            name: 'Classic 350',
            primary: false,
            riddenKm: 80),
      ]
      ..['rides'] = [_miraRide('r1'), _miraRide('r2')]
      ..['follows'] = []
      ..['kudos'] = [];
  });

  testWidgets('a rider\'s name on a ride opens their profile, to follow them',
      (tester) async {
    await _pump(tester, const Scaffold(body: DiscoverScreen()));
    await tester.tap(find.text('Mira Rai').first);
    await _arrive(tester);
    await _settle(tester); // page transition

    expect(find.byType(RiderProfileScreen), findsOneWidget);
    expect(find.text('@mira_rai'), findsOneWidget); // app bar
    expect(find.text('Pokhara · @mira_rai'), findsOneWidget);
    expect(find.text('Weekend twisties, weekday commutes.'), findsOneWidget);
    // Their rides.
    await tester.scrollUntilVisible(find.text('Mira ride r1'), 300);
    expect(find.text('Mira ride r1'), findsOneWidget);
    // Their garage, two to a row.
    await tester.tap(find.text('Garage'));
    await tester.pump();
    final first = tester.getTopLeft(find.text('Himalayan 450'));
    final second = tester.getTopLeft(find.text('Classic 350'));
    expect(second.dy, closeTo(first.dy, 2));
    expect(second.dx, greaterThan(first.dx));
    expect(find.text('PRIMARY'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Follow'), -300);
    await tester.tap(find.text('Follow'));
    await _arrive(tester);
    expect(find.text('Following'), findsOneWidget);
    expect(backend.tables['follows'], [
      {'follower_id': 'me', 'following_id': 'mira'},
    ]);
  });

  testWidgets('their activities, memories, flags and garage', (tester) async {
    backend.tables['rides'] = [
      _miraRide('r1')
        ..['flag_lat'] = 27.71
        ..['flag_lng'] = 85.52,
      _miraRide('r2')
        ..['flag_lat'] = 28.2
        ..['flag_lng'] = 83.98,
    ];
    backend.tables['ride_media'] = [
      for (final (id, ride, kind) in [
        ('m1', 'r1', 'photo'),
        ('m2', 'r1', 'video'),
        ('m3', 'r2', 'photo'),
      ])
        {
          'id': id,
          'ride_id': ride,
          'user_id': 'mira',
          'kind': kind,
          'url': 'https://example.com/$id.jpg',
          'storage_path': 'mira/$ride/$id.jpg',
          'ride': {'id': ride, 'title': 'Mira ride $ride'},
        },
    ];
    await _pump(tester, const RiderProfileScreen(riderId: 'mira'));

    // Activities first.
    for (final tab in ['Activities', 'Memories', 'Flags', 'Garage']) {
      expect(find.text(tab), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text('Mira ride r2'), 300);

    // Memories: every ride's photos and videos, three to a row.
    await tester.tap(find.text('Memories'));
    await _arrive(tester);
    final tiles = find.byType(MediaThumb);
    expect(tiles, findsNWidgets(3));
    expect(tester.getTopLeft(tiles.at(1)).dy,
        closeTo(tester.getTopLeft(tiles.at(0)).dy, 1));
    await tester.tap(tiles.at(2));
    await _settle(tester);
    expect(find.byType(MediaViewer), findsOneWidget);
    expect(find.text('Mira ride r2'), findsWidgets); // where it's from
    await tester.tap(find.byTooltip('Close'));
    await _settle(tester);

    // Flags: where each ride reached; tap one for its ride.
    await tester.tap(find.text('Flags'));
    await _arrive(tester);
    expect(find.text('2 FLAGS'), findsOneWidget);
    expect(find.byType(PlantedFlag), findsNWidgets(2));
    await tester.ensureVisible(find.byType(PlantedFlag).first);
    await tester.pump();
    await tester.tap(find.byType(PlantedFlag).first);
    await tester.pump();
    await _settle(tester);
    expect(find.text('View ride'), findsOneWidget);
    await tester.tap(find.text('View ride'));
    await _arrive(tester);
    await _settle(tester);
    expect(find.byType(RideDetailScreen), findsOneWidget);
  });

  testWidgets('empty tabs say what will be there', (tester) async {
    backend.tables['rides'] = [];
    backend.tables['ride_media'] = [];
    await _pump(tester, const RiderProfileScreen(riderId: 'mira'));
    await tester.tap(find.text('Memories'));
    await _arrive(tester);
    expect(find.text('No memories yet'), findsOneWidget);
    await tester.tap(find.text('Flags'));
    await _arrive(tester);
    expect(find.text('No flags yet'), findsOneWidget);
  });

  testWidgets('your own profile has no Follow button', (tester) async {
    backend.tables['rides'] = [Fixtures.ride()];
    await _pump(
        tester,
        RiderProfileScreen(
            riderId: 'me', initial: Profile.fromJson(Fixtures.profile())));
    expect(find.text('Priya Gurung'), findsWidgets);
    expect(find.text('Follow'), findsNothing);
  });

  group('who can see a ride, after it\'s saved', () {
    testWidgets('your uploaded ride: changed on the server', (tester) async {
      backend.tables['rides'] = [Fixtures.ride(visibility: 'public')];
      final item = FeedItem.fromJson(Fixtures.ride(visibility: 'public'));
      await _pump(tester, RideDetailScreen(item: item));

      await tester.tap(find.text('Public'));
      await _settle(tester);
      expect(find.text('Who can see this ride'), findsOneWidget);
      await tester.tap(find.text('Private'));
      await _arrive(tester);
      await _settle(tester);

      expect(backend.tables['rides']!.single['visibility'], 'private');
      expect(find.text('Private'), findsOneWidget);
    });

    testWidgets('your ride still on the phone: uploads that way',
        (tester) async {
      final pending = PendingRide(
        localId: 'local-1',
        userId: 'me',
        title: 'Ride · 3.0 km',
        visibility: RideVisibility.public,
        distanceKm: 3,
        movingTimeSecs: 600,
        avgSpeedKmh: 18,
        maxSpeedKmh: 40,
        bikeName: 'KTM 390 Duke',
        points: const [],
        createdAt: DateTime(2026, 10, 10),
      );
      LocalRideStore.debugMemory = jsonEncode([pending.toJson()]);
      backend.offline = true;
      final item = FeedItem(
          ride: pending.toRecord(),
          rider: const Profile(id: 'me'),
          pending: true);
      await _pump(tester, RideDetailScreen(item: item));

      await tester.tap(find.text('Public'));
      await _settle(tester);
      await tester.tap(find.text('Followers'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1)); // request retries
      }

      final stored = (await LocalRideStore().pendingUnsynced()).single;
      expect(stored.visibility, RideVisibility.followers);
      expect(find.text('Followers'), findsOneWidget);
      expect(find.textContaining('Couldn\'t change'), findsNothing);
    });

    testWidgets('someone else\'s ride can\'t be changed', (tester) async {
      final item = FeedItem.fromJson(_miraRide('r1'));
      await _pump(tester, RideDetailScreen(item: item));
      expect(find.byIcon(Icons.expand_more), findsNothing);
    });
  });
}
