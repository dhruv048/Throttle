import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:throttle/main.dart';
import 'package:throttle/models/models.dart';
import 'package:throttle/providers/core.dart';
import 'package:throttle/providers/live.dart';
import 'package:throttle/providers/navigation.dart';
import 'package:throttle/providers/recorder.dart';
import 'package:throttle/providers/rider.dart';
import 'package:throttle/providers/rides.dart';
import 'package:throttle/screens/discover_screen.dart';
import 'package:throttle/services/data_changes.dart';
import 'package:throttle/services/local_ride_store.dart';
import 'package:throttle/widgets/map_tiles.dart';

import 'support/fake_gps.dart';
import 'support/fake_places.dart';
import 'support/fake_supabase.dart';
import 'support/providers.dart';

late FakeSupabase backend;

ProviderContainer _container() => ProviderContainer.test(
      retry: noRetry,
      overrides: [placeNamesProvider.overrideWithValue(FakePlaceNames())],
    );

/// Lets pending requests and microtasks run (outside widget tests).
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

/// Settles a widget test's UI once requests have answered.
Future<void> _arrive(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _phone(WidgetTester tester) {
  MapTiles.debugProvider = BlankTiles();
  addTearDown(() => MapTiles.debugProvider = null);
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

FeedItem _item({DateTime? fetchedAt, bool liked = false}) =>
    FeedItem.fromJson(Fixtures.ride(kudos: 4),
        likedByMe: liked, fetchedAt: fetchedAt);

PendingRide _finished() => PendingRide(
      localId: 'ride-1',
      userId: 'me',
      title: 'Ride · 12.3 km',
      visibility: RideVisibility.public,
      distanceKm: 12.3,
      movingTimeSecs: 1800,
      avgSpeedKmh: 24.6,
      maxSpeedKmh: 61,
      bikeName: 'KTM 390 Duke',
      bikeId: 'b1',
      points: const [
        TrackPoint(lat: 27.67, lng: 85.42),
        TrackPoint(lat: 27.71, lng: 85.52),
      ],
      createdAt: DateTime(2026, 10, 10, 9),
    );

void main() {
  setUpAll(() async {
    backend = await FakeSupabase.start(userId: 'me');
  });

  setUp(() {
    LocalRideStore.debugReset();
    backend.reset();
    backend.tables
      ..['profiles'] = [
        Fixtures.profile(),
        Fixtures.profile(
            id: 'mira', username: 'mira_rai', displayName: 'Mira Rai'),
      ]
      ..['bikes'] = [Fixtures.bike()]
      ..['rides'] = [Fixtures.ride()]
      ..['ride_tracks'] = []
      ..['kudos'] = []
      ..['follows'] = [];
  });

  group('live ride counts', () {
    final loaded = DateTime(2026, 10, 11, 9);
    final earlier = loaded.subtract(const Duration(minutes: 1));
    final later = loaded.add(const Duration(minutes: 1));

    test('only counts learnt after a list loaded are shown over it', () {
      final old = const RideCounters()
          .merge(const RideUpdate(id: 'r1', kudosCount: 2), earlier);
      // The list reloaded since: it has the real number.
      expect(old.applyTo(_item(fetchedAt: loaded)).ride.kudosCount, 4);

      final fresh = old.merge(const RideUpdate(id: 'r1', kudosCount: 9), later);
      expect(fresh.applyTo(_item(fetchedAt: loaded)).ride.kudosCount, 9);
    });

    test('each count is judged on its own', () {
      final counters = const RideCounters()
          .merge(const RideUpdate(id: 'r1', kudosCount: 5, likedByMe: true),
              earlier)
          .merge(const RideUpdate(id: 'r1', kudosCount: 7), later);
      // Unliked since (say, on another device): the reload knows that.
      final shown = counters.applyTo(_item(fetchedAt: loaded));
      expect(shown.likedByMe, isFalse);
      expect(shown.ride.kudosCount, 7);
    });

    test('only the most recently changed rides are kept', () {
      final container = _container();
      final counters = container.read(rideCountersProvider.notifier);
      for (var i = 0; i <= RideCountersNotifier.keep; i++) {
        counters.apply(RideUpdate(id: 'r$i', kudosCount: i));
      }
      counters.apply(const RideUpdate(id: 'r1', kudosCount: 99));
      counters.apply(const RideUpdate(id: 'new', kudosCount: 1));

      final kept = container.read(rideCountersProvider);
      expect(kept, hasLength(RideCountersNotifier.keep));
      expect(kept.keys, isNot(contains('r0')));
      expect(kept.keys, isNot(contains('r2')));
      expect(kept['r1']!.kudos!.value, 99);
      expect(kept.keys.last, 'new');
    });

    test('kudos show at once, and are undone if they don\'t go through',
        () async {
      final container = _container();
      final item = _item();
      FeedItem shown() =>
          container.read(rideCountersProvider)['r1']?.applyTo(item) ?? item;

      backend.offline = true;
      final giving =
          container.read(rideCountersProvider.notifier).toggleKudos(item);
      expect(shown().likedByMe, isTrue);
      expect(shown().ride.kudosCount, 5);

      await giving;
      expect(shown().likedByMe, isFalse);
      expect(shown().ride.kudosCount, 4);
    });
  });

  group('changes reach what shows them', () {
    test('a saved or synced ride reloads the feed', () async {
      final container = _container();
      container.listen(homeFeedProvider, (_, __) {});
      expect((await container.read(homeFeedProvider.future)).length, 1);

      backend.tables['rides']!.insert(0, Fixtures.ride(id: 'r2'));
      container.read(dataChangesProvider).rides();
      final feed = await container.read(homeFeedProvider.future);
      expect(feed.map((f) => f.ride.id), ['r2', 'r1']);
    });

    test('following shows at once; it\'s undone (and rethrown) if it fails',
        () async {
      final container = _container();
      container.listen(followingProvider, (_, __) {});
      expect(await container.read(followingProvider.future), isEmpty);

      backend.offline = true;
      final following =
          container.read(followingProvider.notifier).toggle('mira');
      expect(container.read(followingProvider).value, {'mira'});
      await expectLater(following, throwsA(anything));
      expect(container.read(followingProvider).value, isEmpty);
    });

    test('a ride deleted elsewhere: own totals reload, others drop it',
        () async {
      final container = _container();
      container.listen(myRideHistoryProvider, (_, __) {});
      await container.read(myRideHistoryProvider.future); // r1 is mine
      final changes = container.read(dataChangesProvider);

      changes.rideDeleted('someone-elses');
      expect(container.read(deletedRidesProvider), {'someone-elses'});
      expect(container.read(ridesRevisionProvider), 0);

      changes.rideDeleted('r1');
      expect(container.read(deletedRidesProvider), {'someone-elses', 'r1'});
      expect(container.read(ridesRevisionProvider), 1);
    });
  });

  group('recording', () {
    late FakeGeolocator geo;

    setUp(() {
      geo = FakeGeolocator();
      GeolocatorPlatform.instance = geo;
    });
    tearDown(() => geo.fixes.close());

    test('GPS runs while Record is on screen, or a ride is going', () async {
      final container = _container();
      container.listen(rideRecorderProvider, (_, __) {});
      final tabs = container.read(currentTabProvider.notifier);
      final recorder = container.read(rideRecorderProvider.notifier);
      await _settle();
      expect(geo.fixes.hasListener, isFalse, reason: 'on Home');

      tabs.show(AppTab.record);
      await _settle();
      expect(geo.fixes.hasListener, isTrue, reason: 'on Record');

      tabs.show(AppTab.home);
      await _settle();
      expect(geo.fixes.hasListener, isFalse, reason: 'back on Home');

      tabs.show(AppTab.record);
      await _settle();
      recorder.ride();
      tabs.show(AppTab.profile);
      await _settle();
      expect(geo.fixes.hasListener, isTrue, reason: 'riding');

      tabs.show(AppTab.record);
      recorder.finish();
      await _settle();
      expect(container.read(finishedRideProvider), isNotNull);
      expect(geo.fixes.hasListener, isFalse, reason: 'showing the ride');
    });

    test('a save that finishes after Done doesn\'t land on the next ride',
        () async {
      final container = _container();
      container.listen(finishedRideProvider, (_, __) {});
      final finished = container.read(finishedRideProvider.notifier);
      backend.hold = true;
      finished.open(_finished(), elapsedSecs: 1800); // saves straight away
      await _settle();
      expect(container.read(finishedRideProvider)!.saving, isTrue);

      finished.close();
      backend.release();
      await _settle();
      await _settle();
      expect(container.read(finishedRideProvider), isNull);
      expect(backend.tables['rides']!.where((r) => r['local_id'] == 'ride-1'),
          hasLength(1)); // it was still saved
    });
  });

  testWidgets('a ride shared elsewhere appears at the top of Discover',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(withProviders(
        const MaterialApp(home: Scaffold(body: DiscoverScreen()))));
    await _arrive(tester);
    expect(find.text('Nagarkot sunrise run'), findsOneWidget);

    backend.tables['rides']!.add(Fixtures.ride(
        id: 'r2', userId: 'mira', title: 'Kakani loop', kudos: 0));
    tester.container().read(dataChangesProvider).rideAdded('r2');
    // It waits a moment for the ride's GPS track to be written.
    await tester.pump(const Duration(milliseconds: 1600));
    await _arrive(tester);
    expect(find.text('Kakani loop'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Kakani loop')).dy,
        lessThan(tester.getTopLeft(find.text('Nagarkot sunrise run')).dy));

    await tester
        .pump(const Duration(seconds: 3)); // let entrance animations end
  });

  testWidgets('a tab reloads its data when it comes on screen', (tester) async {
    _phone(tester);
    int popularLoads() => backend.requests
        .where((r) => r.url.queryParameters['visibility'] == 'eq.public')
        .length;

    await tester.pumpWidget(withProviders(const ThrottleApp(home: Shell())));
    await _arrive(tester);
    expect(popularLoads(), 1); // every tab loads with the app

    await tester.tap(find.text('DISCOVER'));
    await _arrive(tester);
    expect(popularLoads(), 2);

    await tester.tap(find.text('HOME'));
    await _arrive(tester);
    expect(popularLoads(), 2, reason: 'hidden tabs don\'t reload');

    await tester
        .pump(const Duration(seconds: 3)); // let entrance animations end
  });

  test('signing out starts the next rider afresh', () async {
    final container = _container();
    final changes = container.read(dataChangesProvider);
    container.listen(currentUserIdProvider, (_, __) {});
    container.read(currentTabProvider.notifier).show(AppTab.profile);
    changes.rideUpdated(const RideUpdate(id: 'r1', kudosCount: 9));
    changes.rideDeleted('r9');
    expect(container.read(currentUserIdProvider), 'me');

    await container.read(supabaseClientProvider).auth.signOut();
    await _settle();
    expect(container.read(currentUserIdProvider), isNull);
    expect(container.read(currentTabProvider), AppTab.home);
    expect(container.read(rideCountersProvider), isEmpty);
    expect(container.read(deletedRidesProvider), isEmpty);
    expect(await container.read(myProfileProvider.future), isNull);

    await FakeSupabase.start(userId: 'me'); // signed back in
  });
}
