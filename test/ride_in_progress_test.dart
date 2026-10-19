import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:throttle/providers/navigation.dart';
import 'package:throttle/providers/recorder.dart';
import 'package:throttle/screens/record_screen.dart';
import 'package:throttle/services/local_ride_store.dart';
import 'package:throttle/widgets/map_tiles.dart';

import 'support/fake_gps.dart';
import 'support/fake_supabase.dart';
import 'support/providers.dart';

late FakeSupabase backend;

Future<FakeGeolocator> _pumpRecord(WidgetTester tester,
    {FakeGeolocator? geo}) async {
  geo ??= FakeGeolocator();
  GeolocatorPlatform.instance = geo;
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(withProviders(
    const MaterialApp(home: Scaffold(body: RecordScreen())),
    tab: AppTab.record,
  ));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return geo;
}

/// Rides [metres] north at 5 m/s, a fix a second, from [fromM].
Future<void> _rideNorth(WidgetTester tester, FakeGeolocator geo,
    {required double fromM, required double metres}) async {
  final t0 = DateTime.now();
  final fixes = (metres / 5).round();
  for (var i = 0; i <= fixes; i++) {
    geo.fixes.add(fixAt(t0.add(Duration(seconds: i)), fromM + i * 5.0));
    await tester.pump(const Duration(seconds: 1));
  }
}

Map<String, dynamic>? get _kept => LocalRideStore.debugLive == null
    ? null
    : jsonDecode(LocalRideStore.debugLive!) as Map<String, dynamic>;

/// Lets a dialog open or close (the ride's clock never settles).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Unmounts the app, as if it were closed.
Future<void> _closeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  setUpAll(() async {
    backend = await FakeSupabase.start(userId: 'me');
    MapTiles.debugProvider = BlankTiles();
  });

  setUp(() {
    LocalRideStore.debugReset();
    backend.reset();
    backend.tables
      ..['profiles'] = [Fixtures.profile()]
      ..['bikes'] = [
        Fixtures.bike(),
        Fixtures.bike(id: 'b2', name: 'Yamaha MT-15', primary: false),
      ];
  });

  group('the ride in progress', () {
    testWidgets('is kept on the phone every few seconds while riding',
        (tester) async {
      final geo = await _pumpRecord(tester);
      await tester.tap(find.text('START'));
      await tester.pump();
      await _rideNorth(tester, geo, fromM: 0, metres: 100);

      final kept = _kept!;
      expect(kept['userId'], 'me');
      expect(kept['bikeId'], 'b1');
      expect(kept['secs'], greaterThanOrEqualTo(RideRecorder.persistEverySecs));
      final tracker = kept['tracker'] as Map;
      expect(tracker['distanceM'], greaterThan(50));
      expect((tracker['points'] as List).length, greaterThan(5));
      // Stored compactly.
      final point = (tracker['points'] as List).first as Map;
      expect('${point['lat']}'.split('.').last.length, lessThanOrEqualTo(6));

      await tester.tap(find.text('FINISH'));
      await _settle(tester);
      expect(LocalRideStore.debugLive, isNull); // now it's a finished ride
      // Saved straight away.
      final saved = (await LocalRideStore().loadAll()).single;
      expect(saved.distanceKm, greaterThan(0.05));
      await _settle(tester);
    });

    testWidgets('comes back paused after the app is closed, and carries on',
        (tester) async {
      var geo = await _pumpRecord(tester);
      // Ride on the second bike.
      await tester.tap(find.text('Yamaha MT-15'));
      await tester.pump();
      await tester.tap(find.text('START'));
      await tester.pump();
      await _rideNorth(tester, geo, fromM: 0, metres: 150);
      final before = (_kept!['tracker'] as Map)['distanceM'] as num;
      await geo.fixes.close();

      await _closeApp(tester);
      geo = await _pumpRecord(tester); // opened again

      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.textContaining('Throttle was closed during this ride'),
          findsOneWidget);
      expect(find.text('RESUME'), findsOneWidget);
      expect(find.text('Choose your ride'), findsNothing);

      await tester.tap(find.text('RESUME'));
      await tester.pump();
      expect(find.textContaining('Throttle was closed'), findsNothing);
      await _rideNorth(tester, geo, fromM: 400, metres: 100);
      await tester.tap(find.text('FINISH'));
      await _settle(tester);
      await geo.fixes.close();

      // One ride: what was kept, plus what came after.
      final saved = (await LocalRideStore().loadAll()).single;
      expect(saved.distanceKm * 1000, greaterThan(before + 80));
      expect(saved.bikeId, 'b2');
      expect(saved.bikeName, 'Yamaha MT-15');
      await _settle(tester);
    });

    testWidgets('another rider\'s ride isn\'t shown', (tester) async {
      LocalRideStore.debugLive = jsonEncode({
        'userId': 'someone-else',
        'secs': 60,
        'tracker': {'distanceM': 500, 'points': <Object>[]},
      });
      final geo = await _pumpRecord(tester);
      expect(find.text('Choose your ride'), findsOneWidget);
      expect(LocalRideStore.debugLive, isNotNull); // kept for them
      await geo.fixes.close();
    });
  });

  group('background location', () {
    testWidgets('allowed only while using the app: asked once, at START',
        (tester) async {
      final geo = FakeGeolocator()
        ..permission = LocationPermission.whileInUse
        ..answer = LocationPermission.always;
      await _pumpRecord(tester, geo: geo);
      expect(find.text('Keep recording with the screen off'), findsNothing);

      await tester.tap(find.text('START'));
      await _settle(tester);
      expect(find.text('Keep recording with the screen off'), findsOneWidget);
      await tester.tap(find.text('Allow all the time'));
      await _settle(tester);
      expect(geo.requests, 1);
      expect(find.text('Keep recording with the screen off'), findsNothing);
      // Recording carried on underneath.
      expect(find.text('RECORDING'), findsOneWidget);
      await geo.fixes.close();
    });

    testWidgets('"Not now" isn\'t asked again in the same session',
        (tester) async {
      final geo = FakeGeolocator()..permission = LocationPermission.whileInUse;
      await _pumpRecord(tester, geo: geo);
      await tester.tap(find.text('START'));
      await _settle(tester);
      await tester.tap(find.text('Not now'));
      await _settle(tester);
      expect(geo.requests, 0);

      await tester.tap(find.text('FINISH'));
      await _settle(tester);
      await tester.tap(find.text('DISCARD'));
      await _settle(tester);
      await tester.tap(find.text('START'));
      await _settle(tester);
      expect(find.text('Keep recording with the screen off'), findsNothing);
      await geo.fixes.close();
    });

    testWidgets('asked right after the rider picks "while using the app"',
        (tester) async {
      final geo = FakeGeolocator()
        ..permission = LocationPermission.denied
        ..answer = LocationPermission.whileInUse;
      await _pumpRecord(tester, geo: geo);
      await _settle(tester);
      expect(geo.requests, 1); // the system's own prompt
      expect(find.text('Keep recording with the screen off'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await _settle(tester);
      await geo.fixes.close();
    });

    testWidgets('allowed all the time: never asked', (tester) async {
      final geo = await _pumpRecord(tester);
      await tester.tap(find.text('START'));
      await _settle(tester);
      expect(find.text('Keep recording with the screen off'), findsNothing);
      await geo.fixes.close();
    });
  });
}
