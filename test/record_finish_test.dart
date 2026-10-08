import 'dart:async';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:throttle/screens/record_screen.dart';
import 'package:throttle/screens/share_ride_screen.dart';
import 'package:throttle/widgets/map_tiles.dart';
import 'package:throttle/widgets/bike_chooser.dart';
import 'package:throttle/widgets/live_ride_map.dart';

/// Map tiles without the network: a 1×1 transparent PNG for every tile.
class _BlankTiles extends TileProvider {
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_png);
}

/// GPS the test can drive by hand.
class _FakeGeolocator extends GeolocatorPlatform {
  final fixes = StreamController<Position>.broadcast();

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      fixes.stream;
}

Position _fix(DateTime t, double northM) => Position(
      latitude: 27.7 + northM / 111320,
      longitude: 85.3,
      timestamp: t,
      accuracy: 5,
      altitude: 1300,
      altitudeAccuracy: 3,
      heading: 0,
      headingAccuracy: 1,
      speed: 5,
      speedAccuracy: 0.3,
    );

void main() {
  testWidgets(
      'SHARE RIDE shows the moment the ride ends, before saving finishes',
      (tester) async {
    final geo = _FakeGeolocator();
    GeolocatorPlatform.instance = geo;
    MapTiles.debugProvider = _BlankTiles();
    addTearDown(() => MapTiles.debugProvider = null);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: RecordScreen())));
    await tester.pump();

    // Before the ride: the motorcycle chooser.
    expect(find.text('Choose your ride'), findsOneWidget);
    expect(find.byType(BikeChooser), findsOneWidget);
    expect(find.byType(LiveRideMap), findsNothing);

    await tester.tap(find.text('START'));
    await tester.pump();

    // Ride ~150 m north at 18 km/h.
    final t0 = DateTime.now();
    for (var i = 0; i <= 30; i++) {
      geo.fixes.add(_fix(t0.add(Duration(seconds: i)), i * 5.0));
      await tester.pump();
    }

    // During the ride: live map with the stats overlaid.
    expect(find.byType(LiveRideMap), findsOneWidget);
    expect(find.text('RECORDING'), findsOneWidget);
    // Speed and average are both 18 km/h at a steady 5 m/s.
    expect(find.text('18 km/h', findRichText: true), findsNWidgets(2));
    expect(find.text('0.15 km', findRichText: true), findsOneWidget);
    final map = tester.widget<LiveRideMap>(find.byType(LiveRideMap));
    expect(map.trail.length, greaterThan(10)); // a point every ~10 m here
    expect(map.here!.latitude, closeTo(27.7 + 150 / 111320, 1e-9));

    await tester.tap(find.text('PAUSE'));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.text('RESUME'), findsOneWidget);

    await tester.tap(find.text('FINISH'));
    await tester.pump(); // one frame: no waiting on the save

    expect(find.text('SHARE RIDE'), findsOneWidget);
    // On screen without scrolling (390×844 logical phone).
    expect(tester.getRect(find.text('SHARE RIDE')).bottom, lessThan(844));
    // Distance on the summary.
    expect(find.textContaining('0.15'), findsWidgets);

    // Supabase isn't initialised in tests, so the save fails. Sharing must
    // not depend on it.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Couldn\'t save this ride'), findsOneWidget);
    expect(find.text('Retry save'), findsOneWidget);
    expect(find.text('SHARE RIDE'), findsOneWidget);

    await tester.tap(find.text('SHARE RIDE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ShareRideScreen), findsOneWidget);
    expect(find.text('Share ride'), findsOneWidget); // share screen app bar
    expect(
        find.textContaining('0.15'), findsWidgets); // same distance on the card

    await geo.fixes.close();
  });
}
