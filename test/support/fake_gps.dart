import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';

/// Map tiles without the network: a 1×1 transparent PNG for every tile.
class BlankTiles extends TileProvider {
  static final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(png);
}

/// GPS the test can drive by hand.
class FakeGeolocator extends GeolocatorPlatform {
  final fixes = StreamController<Position>.broadcast();

  /// What the rider has allowed. [requestPermission] answers with
  /// [answer] (when set) and remembers it.
  LocationPermission permission = LocationPermission.always;
  LocationPermission? answer;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return permission = answer ?? permission;
  }

  @override
  Future<bool> openAppSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      fixes.stream;
}

/// A good fix [northM] metres north of a fixed start, moving at 5 m/s.
Position fixAt(DateTime t, double northM) => Position(
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
