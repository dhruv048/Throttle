import 'package:flutter_map/flutter_map.dart';

/// OpenStreetMap tiles shared by every map in the app.
class MapTiles {
  MapTiles._();

  /// Lets tests serve tiles without the network. Null = OpenStreetMap.
  static TileProvider? debugProvider;

  static TileLayer layer() => TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.wheelsclub.wheelsclub',
        tileProvider: debugProvider,
      );
}
