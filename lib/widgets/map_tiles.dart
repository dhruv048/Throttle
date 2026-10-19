import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// OpenStreetMap tiles shared by every map in the app.
class MapTiles {
  MapTiles._();

  /// Lets tests serve tiles without the network. Null = OpenStreetMap.
  static TileProvider? debugProvider;

  /// One map tile, as a picture (e.g. to wrap a globe in).
  static ImageProvider tileImage(int z, int x, int y) =>
      debugProvider?.getImage(TileCoordinates(x, y, z), layer()) ??
      NetworkImage(
        'https://tile.openstreetmap.org/$z/$x/$y.png',
        headers: const {
          'User-Agent': 'flutter_map (com.wheelsclub.wheelsclub)',
        },
      );

  /// [dark] shows the tiles in night colours.
  static TileLayer layer({bool dark = false}) => TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.wheelsclub.wheelsclub',
        tileProvider: debugProvider,
        tileBuilder: dark ? darkModeTileBuilder : null,
      );
}
