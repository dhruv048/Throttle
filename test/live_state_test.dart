import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:throttle/models/models.dart';
import 'package:throttle/providers/live.dart';
import 'package:throttle/screens/activity_screen.dart';
import 'package:throttle/screens/discover_screen.dart';
import 'package:throttle/screens/home_screen.dart';
import 'package:throttle/screens/profile_screen.dart';
import 'package:throttle/screens/record_screen.dart';
import 'package:throttle/services/data_changes.dart';
import 'package:throttle/services/local_ride_store.dart';
import 'package:throttle/widgets/map_tiles.dart';
import 'package:throttle/widgets/ride_card.dart';
import 'package:throttle/widgets/skeleton.dart';
import 'package:throttle/widgets/ui.dart';

import 'support/fake_supabase.dart';
import 'support/providers.dart';

/// Map tiles without the network: a 1×1 transparent PNG.
class _BlankTiles extends TileProvider {
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_png);
}

late FakeSupabase backend;

Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester
      .pumpWidget(withProviders(MaterialApp(home: Scaffold(body: screen))));
  await tester.pump();
}

/// What this app's writes and Realtime report changes to.
DataChanges _changes(WidgetTester tester) =>
    tester.container().read(dataChangesProvider);

/// The value shown on the stat tile labelled [label].
String? _stat(String label) {
  final tile =
      find.ancestor(of: find.text(label), matching: find.byType(AppCard)).first;
  final texts = find.descendant(of: tile, matching: find.byType(Text));
  return (texts.evaluate().first.widget as Text).data;
}

/// Lets held requests through and settles the UI.
Future<void> _arrive(WidgetTester tester) async {
  backend.release();
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    backend = await FakeSupabase.start(userId: 'me');
    MapTiles.debugProvider = _BlankTiles();
  });

  setUp(() {
    LocalRideStore.debugMemory = '[]';
    backend.reset();
    backend.tables
      ..['profiles'] = [Fixtures.profile()]
      ..['bikes'] = [Fixtures.bike()]
      ..['rides'] = [Fixtures.ride()]
      ..['kudos'] = []
      ..['follows'] = [];
  });

  group('while loading: skeletons, never made-up data', () {
    testWidgets('Home', (tester) async {
      backend.tables['rides'] = [
        Fixtures.ride()
          ..['flag_lat'] = 27.71
          ..['flag_lng'] = 85.52
          ..['end_place'] = 'Nagarkot',
      ];
      backend.hold = true;
      await _pumpScreen(tester, const HomeScreen());

      expect(find.byType(Shimmer), findsWidgets);
      expect(find.text('Add a bike in Profile'), findsNothing);
      expect(find.textContaining('Every ride plants a flag'), findsNothing);
      expect(find.textContaining('Couldn'), findsNothing);

      await _arrive(tester);
      expect(find.byType(Shimmer), findsNothing);
      expect(
        find.textContaining(RegExp('(Morning|Afternoon|Evening), Priya'),
            findRichText: true),
        findsOneWidget,
      );
      expect(find.text('KTM 390 Duke'), findsOneWidget);
      // The rider's own flags, not other riders' rides.
      expect(find.text('FLAG PLANTED'), findsOneWidget);
      expect(find.text('PLACES YOU\'VE REACHED'), findsOneWidget);
      expect(find.text('Nagarkot'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4)); // the flight in
    });

    testWidgets('Activity: no zero totals before the history arrives',
        (tester) async {
      backend.hold = true;
      await _pumpScreen(tester, const ActivityScreen());

      expect(find.byType(Shimmer), findsWidgets);
      expect(find.text('0'), findsNothing);
      expect(find.text('0.0'), findsNothing);
      expect(find.textContaining('No rides yet'), findsNothing);

      await _arrive(tester);
      expect(_stat('KM RIDDEN'), '22.4'); // this year
      expect(_stat('RIDES'), '1');
      // What they've earned, then their rides.
      expect(find.text('ACHIEVEMENTS'), findsOneWidget);
      expect(find.text('First flag'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Nagarkot sunrise run'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Nagarkot sunrise run'), findsOneWidget);
    });

    testWidgets('Profile: no placeholder counts or names', (tester) async {
      backend.hold = true;
      await _pumpScreen(tester, const ProfileScreen());

      expect(find.byType(Shimmer), findsWidgets);
      expect(find.text('–'), findsNothing);
      expect(find.text('Priya Gurung'), findsNothing);

      await _arrive(tester);
      // Header, plus the rider name on their recent ride card.
      expect(find.text('Priya Gurung'), findsNWidgets(2));
      expect(
          find.text('@priya_g · Bhaktapur', findRichText: true), findsNothing);
      expect(find.text('Bhaktapur · @priya_g'), findsOneWidget);
      expect(find.text('Hide start & end near home'), findsNothing);
      // The garage is a tab; flags are on Home.
      expect(find.text('Flags'), findsNothing);
      await tester.tap(find.text('Garage'));
      await tester.pump();
      expect(find.textContaining('412.3 km ridden'), findsOneWidget);
    });

    testWidgets('Record: bike chooser shows placeholders, not "no bike"',
        (tester) async {
      backend.hold = true;
      await _pumpScreen(tester, const RecordScreen());

      expect(find.byType(Shimmer), findsWidgets);
      expect(find.textContaining('Couldn'), findsNothing);
      expect(find.textContaining('Add your bike'), findsNothing);

      await _arrive(tester);
      expect(find.text('KTM 390 Duke'), findsOneWidget);
      expect(find.byType(Shimmer), findsNothing);
    });
  });

  group('changes show up live, everywhere', () {
    testWidgets('a kudos count change reaches every card for that ride',
        (tester) async {
      await _pumpScreen(tester, const DiscoverScreen());
      await _arrive(tester);
      expect(find.text('4'), findsOneWidget);

      // E.g. pushed by Realtime when another rider gives kudos.
      _changes(tester).rideUpdated(const RideUpdate(id: 'r1', kudosCount: 9));
      await tester.pump();
      expect(find.text('9'), findsOneWidget);
    });

    testWidgets('kudos tapped on one card updates other cards for the ride',
        (tester) async {
      final item = FeedItem.fromJson(Fixtures.ride());
      await _pumpScreen(
        tester,
        ListView(children: [
          RideCard(key: const ValueKey('a'), item: item),
          RideCard(key: const ValueKey('b'), item: item),
        ]),
      );
      expect(find.text('4'), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.favorite_border).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('5'), findsNWidgets(2));
      expect(find.byIcon(Icons.favorite), findsNWidgets(2));
      expect(backend.writes('kudos'), hasLength(1));
    });

    testWidgets('a bike added elsewhere appears in the Record chooser',
        (tester) async {
      await _pumpScreen(tester, const RecordScreen());
      await _arrive(tester);
      expect(find.text('Royal Enfield Himalayan'), findsNothing);

      backend.tables['bikes']!.add(Fixtures.bike(
          id: 'b2', name: 'Royal Enfield Himalayan', primary: false));
      _changes(tester).bikes(); // from BikeRepository or Realtime
      await _arrive(tester);
      expect(find.text('Royal Enfield Himalayan'), findsOneWidget);
    });

    testWidgets('a deleted ride disappears from Discover', (tester) async {
      await _pumpScreen(tester, const DiscoverScreen());
      await _arrive(tester);
      expect(find.text('Nagarkot sunrise run'), findsOneWidget);

      _changes(tester).rideDeleted('r1');
      await tester.pump();
      expect(find.text('Nagarkot sunrise run'), findsNothing);
    });

    testWidgets('following a rider in Discover is real and sticks',
        (tester) async {
      backend.tables['profiles']!.add(Fixtures.profile(
          id: 'mira', username: 'mira_rai', displayName: 'Mira Rai'));
      await _pumpScreen(tester, const DiscoverScreen());
      await _arrive(tester);
      final container = tester.container();
      final before = container.read(followsRevisionProvider);

      await tester.tap(find.text('RIDERS'));
      await tester.pump();
      expect(find.text('Mira Rai'), findsOneWidget);
      expect(find.text('Priya Gurung'), findsNothing); // not yourself

      await tester.tap(find.text('Follow'));
      await _arrive(tester);
      expect(find.text('Following'), findsOneWidget);
      expect(backend.tables['follows'], [
        {'follower_id': 'me', 'following_id': 'mira'},
      ]);
      // Everything showing who the rider follows reloads.
      expect(container.read(followsRevisionProvider), greaterThan(before));
    });
  });

  testWidgets('Discover: riders by badges earned, and who holds each record',
      (tester) async {
    Map<String, dynamic> standing(String id, String name,
            {int rides = 1,
            double km = 10,
            double longest = 10,
            double climb = 0,
            int places = 0}) =>
        {
          'id': id,
          'username': id,
          'display_name': name,
          'rides': rides,
          'total_km': km,
          'longest_km': longest,
          'climb_m': climb,
          'biggest_climb_m': climb,
          'places': places,
          'longest_secs': 1800,
        };
    backend.tables['rpc/rider_leaderboard'] = [
      // Most km, but fewer badges.
      standing('sam', 'Sam Lama', rides: 2, km: 900, longest: 450),
      standing('mira', 'Mira Rai',
          rides: 12, km: 400, longest: 120, climb: 1500, places: 6),
      standing('me', 'Priya Gurung'),
    ];
    await _pumpScreen(tester, const DiscoverScreen());
    await _arrive(tester);
    await tester.tap(find.text('ACHIEVEMENTS'));
    await tester.pump();

    expect(find.text('MOST ACHIEVEMENTS'), findsOneWidget);
    final mira = tester.getTopLeft(find.text('Mira Rai').first).dy;
    final sam = tester.getTopLeft(find.text('Sam Lama').first).dy;
    expect(mira, lessThan(sam)); // more badges ranks higher
    expect(find.text('Priya Gurung (you)'), findsOneWidget);
    expect(find.text('8 badges · 400.0 km'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('MOST CLIMBED'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('RECORD HOLDERS'), findsOneWidget);
    expect(find.text('900.0 km'), findsOneWidget); // most km: Sam
    expect(find.text('450.0 km'), findsOneWidget); // longest ride: Sam
    expect(find.text('1,500 m'), findsOneWidget); // most climbed: Mira
  });
}
