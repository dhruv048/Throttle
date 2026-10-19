import 'package:throttle/services/place_names.dart';

/// Names places without the network: [name] for every point (null: none).
class FakePlaceNames extends PlaceNames {
  FakePlaceNames({this.name, this.names = const {}});

  final String? name;

  /// By rounded "lat,lng" (3 decimals), before [name].
  final Map<String, String> names;
  final asked = <String>[];

  @override
  Future<String?> nameOf(double lat, double lng) async {
    final key = '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
    asked.add(key);
    return names[key] ?? name;
  }
}
