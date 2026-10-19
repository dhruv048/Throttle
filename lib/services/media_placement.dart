import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/models.dart';
import 'ride_tracker.dart' show haversineM;

/// What a photo says about itself: where and when it was taken.
class PhotoMeta {
  const PhotoMeta({this.lat, this.lng, this.takenAt});

  final double? lat;
  final double? lng;
  final DateTime? takenAt;

  bool get hasLocation => lat != null && lng != null;
}

/// Reads [jpeg]'s EXIF GPS position and capture time, when it has them.
/// Phones record both for camera photos (if location is on); screenshots and
/// edited images often have neither.
PhotoMeta readPhotoMeta(Uint8List jpeg) {
  final img.ExifData? exif;
  try {
    exif = img.decodeJpgExif(jpeg);
  } catch (_) {
    return const PhotoMeta();
  }
  if (exif == null) return const PhotoMeta();

  double? coordinate(int valueTag, int refTag, String negative) {
    final value = exif!.gpsIfd.data[valueTag];
    if (value == null || value.length == 0) return null;
    // Degrees, minutes, seconds (some writers give just decimal degrees).
    var degrees = value.toDouble(0);
    if (value.length >= 2) degrees += value.toDouble(1) / 60;
    if (value.length >= 3) degrees += value.toDouble(2) / 3600;
    if (!degrees.isFinite) return null;
    final ref = exif.gpsIfd.data[refTag]?.toString().trim().toUpperCase();
    return ref == negative ? -degrees : degrees;
  }

  var lat = coordinate(0x0002, 0x0001, 'S');
  var lng = coordinate(0x0004, 0x0003, 'W');
  // 0,0 is what some cameras write when they have no fix.
  if (lat == null || lng == null || (lat == 0 && lng == 0)) {
    lat = null;
    lng = null;
  }

  return PhotoMeta(lat: lat, lng: lng, takenAt: _takenAt(exif));
}

/// EXIF DateTimeOriginal ("2026:10:09 06:42:10") is the phone's local time,
/// with its UTC offset ("+05:45") alongside when the camera wrote one.
DateTime? _takenAt(img.ExifData exif) {
  final raw = (exif.exifIfd.data[0x9003] ?? exif.imageIfd.data[0x0132])
      ?.toString()
      .trim();
  if (raw == null) return null;
  final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})')
      .firstMatch(raw);
  if (m == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  if (parts[0] < 1990) return null;
  final offset = exif.exifIfd.data[0x9011]?.toString().trim();
  final o = offset == null
      ? null
      : RegExp(r'^([+-])(\d{2}):(\d{2})').firstMatch(offset);
  if (o == null) {
    return DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
  }
  final sign = o.group(1) == '-' ? -1 : 1;
  final shift =
      Duration(hours: int.parse(o.group(2)!), minutes: int.parse(o.group(3)!));
  return DateTime.utc(
          parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])
      .subtract(shift * sign);
}

/// How a photo or video found its place on the route.
enum PlacedBy {
  /// Its GPS position is on (or near) the route.
  location,

  /// It was taken during the ride: where the rider was at that moment.
  time,
}

class RoutePlace {
  const RoutePlace(this.index, this.by);

  /// Into the ride's track.
  final int index;
  final PlacedBy by;
}

/// Where on [track] something taken at [lat]/[lng], or at [takenAt], goes:
/// the nearest point to where it was taken, if that's within [maxOffRouteM]
/// of the route, else where the rider was when it was taken, if that was
/// during the ride (give or take [slack]). Null if neither says.
RoutePlace? placeOnRoute(
  List<TrackPoint> track, {
  double? lat,
  double? lng,
  DateTime? takenAt,
  double maxOffRouteM = 500,
  Duration slack = const Duration(minutes: 15),
}) {
  if (track.isEmpty) return null;

  if (lat != null && lng != null) {
    var best = 0;
    var bestM = double.infinity;
    for (var i = 0; i < track.length; i++) {
      final d = haversineM(lat, lng, track[i].lat, track[i].lng);
      if (d < bestM) {
        bestM = d;
        best = i;
      }
    }
    if (bestM <= maxOffRouteM) return RoutePlace(best, PlacedBy.location);
  }

  final when = takenAt?.toUtc();
  final start = track.first.t?.toUtc();
  final end = track.last.t?.toUtc();
  if (when != null &&
      start != null &&
      end != null &&
      !when.isBefore(start.subtract(slack)) &&
      !when.isAfter(end.add(slack))) {
    var best = 0;
    var bestGap = double.infinity;
    for (var i = 0; i < track.length; i++) {
      final t = track[i].t;
      if (t == null) continue;
      final gap = t.toUtc().difference(when).inMilliseconds.abs().toDouble();
      if (gap < bestGap) {
        bestGap = gap;
        best = i;
      }
    }
    return RoutePlace(best, PlacedBy.time);
  }
  return null;
}

/// The index of [track]'s point nearest to [lat]/[lng] (for something
/// already placed).
int nearestIndex(List<TrackPoint> track, double lat, double lng) {
  var best = 0;
  var bestM = double.infinity;
  for (var i = 0; i < track.length; i++) {
    final d = haversineM(lat, lng, track[i].lat, track[i].lng);
    if (d < bestM) {
      bestM = d;
      best = i;
    }
  }
  return best;
}

/// Distance along [track] to each of its points, in km.
List<double> distanceAlongKm(List<TrackPoint> track) {
  final out = List<double>.filled(track.length, 0);
  for (var i = 1; i < track.length; i++) {
    out[i] = out[i - 1] +
        haversineM(track[i - 1].lat, track[i - 1].lng, track[i].lat,
                track[i].lng) /
            1000;
  }
  return out;
}
