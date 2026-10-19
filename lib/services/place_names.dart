import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Names the place at a point ("Nagarkot", "Pokhara"): the village, town or
/// city a ride set off from or reached. Looked up with OpenStreetMap's
/// Nominatim, at most one request a second as its usage policy asks
/// (https://operations.osmfoundation.org/policies/nominatim/); a busy app
/// should move to its own geocoder.
class PlaceNames {
  PlaceNames({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final _cache = <String, Future<String?>>{};

  /// When the next request may go out.
  Future<void> _turn = Future.value();

  static const _userAgent = 'Throttle/1.0 (com.wheelsclub.wheelsclub)';

  /// The name of the place at [lat], [lng], or null if it can't be found
  /// (offline, the sea, nowhere in particular).
  Future<String?> nameOf(double lat, double lng) {
    // Within ~100 m is the same place.
    final key = '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
    return _cache[key] ??= _queued(lat, lng).then((name) {
      if (name == null) _cache.remove(key); // try again next time
      return name;
    });
  }

  Future<String?> _queued(double lat, double lng) {
    final result = _turn.then((_) => _fetch(lat, lng));
    _turn = result
        .then<void>((_) {}, onError: (_) {})
        .then((_) => Future<void>.delayed(const Duration(milliseconds: 1100)));
    return result;
  }

  Future<String?> _fetch(double lat, double lng) async {
    try {
      final response = await _client.get(
        Uri.https('nominatim.openstreetmap.org', '/reverse', {
          'format': 'jsonv2',
          'lat': '$lat',
          'lon': '$lng',
          'zoom': '14',
          'accept-language': 'en',
        }),
        headers: const {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      return nameFrom(jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (e) {
      debugPrint('Couldn\'t name the place at $lat,$lng: $e');
      return null;
    }
  }

  /// The best name in a Nominatim reverse-geocoding [result]: the
  /// settlement first, then wider areas.
  @visibleForTesting
  static String? nameFrom(Object? result) {
    if (result is! Map) return null;
    final address = result['address'];
    if (address is Map) {
      for (final key in const [
        'village',
        'town',
        'city',
        'municipality',
        'hamlet',
        'suburb',
        'city_district',
        'county',
        'state_district',
        'state',
      ]) {
        final name = address[key];
        if (name is String && name.trim().isNotEmpty) return name.trim();
      }
    }
    final name = result['name'];
    return name is String && name.trim().isNotEmpty ? name.trim() : null;
  }
}

/// "Bhaktapur → Nagarkot", "Around Pokhara", "To Nagarkot": where a ride
/// went, as far as its place names are known. Null if neither is.
String? placesLine(String? start, String? end) {
  if (start == null && end == null) return null;
  if (start == null) return 'To $end';
  if (end == null) return 'From $start';
  if (start == end) return 'Around $start';
  return '$start → $end';
}

/// Names the places [flags] reached that have no name yet (rides from
/// before places were named), a few at a time, saving each with [save].
/// Returns how many were named.
Future<int> nameReachedPlaces(
  PlaceNames places,
  List<RideFlag> flags,
  Future<void> Function(String rideId, String place) save, {
  int max = 10,
}) async {
  var named = 0;
  for (final f in flags.where((f) => f.place == null && !f.pending).take(max)) {
    final name = await places.nameOf(f.lat, f.lng);
    if (name == null) continue;
    try {
      await save(f.rideId, name);
      named++;
    } catch (e) {
      debugPrint('Couldn\'t save the place name: $e');
    }
  }
  return named;
}
