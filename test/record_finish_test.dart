import 'dart:async';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:throttle/screens/record_screen.dart';
import 'package:throttle/screens/share_ride_screen.dart';
import 'package:throttle/widgets/tracked_route_map.dart';

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
    TrackedRouteMap.debugTileProvider = _BlankTiles();
    addTearDown(() => TrackedRouteMap.debugTileProvider = null);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: RecordScreen())));
    await tester.pump();

    await tester.tap(find.text('START'));
    await tester.pump();

    // Ride ~150 m north at 18 km/h.
    final t0 = DateTime.now();
    for (var i = 0; i <= 30; i++) {
      geo.fixes.add(_fix(t0.add(Duration(seconds: i)), i * 5.0));
      await tester.pump();
    }

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
