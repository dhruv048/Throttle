import 'dart:math' as math;

import '../models/models.dart';

/// One location update, decoupled from geolocator so the maths is testable.
class GpsFix {
  const GpsFix({
    required this.lat,
    required this.lng,
    required this.time,
    this.accuracyM = 5,
    this.speedMps,
    this.speedAccuracyMps,
    this.altitudeM,
    this.altitudeAccuracyM,
  });

  final double lat;
  final double lng;
  final DateTime time;

  /// Horizontal accuracy radius in metres.
  final double accuracyM;

  /// Device-reported (Doppler) ground speed. Negative when unknown (iOS).
  final double? speedMps;

  /// 0 or negative means the platform has no speed estimate (Android reports
  /// speed 0.0 in that case). Null means "not provided": trust [speedMps].
  final double? speedAccuracyMps;
  final double? altitudeM;
  final double? altitudeAccuracyM;

  bool get hasSpeed {
    final v = speedMps;
    if (v == null || !v.isFinite || v < 0) return false;
    final acc = speedAccuracyMps;
    return acc == null || acc > 0;
  }
}

double haversineM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double toR(double d) => d * math.pi / 180;
  final dLat = toR(lat2 - lat1);
  final dLon = toR(lon2 - lon1);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(toR(lat1)) *
          math.cos(toR(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(h)));
}

/// Turns a noisy GPS stream into ride distance, moving time, top speed and
/// climb.
///
/// Summing raw fix-to-fix distances over-counts badly: a parked phone wanders
/// a few metres every second, and sideways noise lengthens every segment.
/// So:
/// - Distance is measured from the last accepted fix (the anchor) and only
///   committed once the rider has clearly moved beyond both fixes' error.
///   Jitter is ignored; slow movement just lands in bigger chunks.
/// - When the device reports Doppler speed (far more precise than position),
///   a known zero speed means "stopped", and short moving segments are
///   measured as speed × time, which also follows curves instead of cutting
///   chords.
class RideTracker {
  RideTracker({
    this.maxAccuracyM = 30,
    this.minStepM = 5,
    this.glitchSpeedKmh = 250,
    this.movingSpeedMps = 1.0,
    this.climbThresholdM = 4,
  });

  /// Fixes less accurate than this are ignored entirely.
  final double maxAccuracyM;

  /// Smallest step committed while clearly moving.
  final double minStepM;

  /// Implied speeds above this are GPS glitches (teleports).
  final double glitchSpeedKmh;

  /// Segments are credited moving time at no less than this speed, so a long
  /// stop followed by a few metres of movement doesn't count as riding.
  final double movingSpeedMps;

  /// Altitude hysteresis; smaller rises are treated as noise.
  final double climbThresholdM;

  static const _stoppedMps = 0.5;
  static const _movingMps = 2.0;
  static const _maxDopplerGapSecs = 3.0;

  bool _recording = false;
  GpsFix? _anchor;
  GpsFix? _lastGood;
  final List<GpsFix> _rejectedJumps = [];
  double? _elevRef;

  double distanceM = 0;
  double movingSecs = 0;
  double maxSpeedKmh = 0;
  double elevationGainM = 0;
  double currentSpeedKmh = 0;
  final List<TrackPoint> points = [];

  bool get recording => _recording;
  double get distanceKm => distanceM / 1000;
  double get avgSpeedKmh =>
      movingSecs > 0 ? distanceKm / (movingSecs / 3600) : 0;

  /// Latest fix with acceptable accuracy, recording or not.
  GpsFix? get lastGoodFix => _lastGood;

  /// Starts or resumes recording.
  void start({DateTime? now}) {
    _recording = true;
    _anchor = null;
    _rejectedJumps.clear();
    // Seed the track with the current position so the ride starts where the
    // rider pressed START, not at the first post-start fix.
    final here = _lastGood;
    if (here != null &&
        (now ?? DateTime.now()).difference(here.time) <
            const Duration(seconds: 10)) {
      _accept(here);
    }
  }

  /// Pauses (or finishes) recording. Distance travelled while paused is
  /// never counted.
  void pause() {
    if (_recording) _flushTail();
    _recording = false;
    _anchor = null;
    _rejectedJumps.clear();
  }

  void reset() {
    pause();
    distanceM = 0;
    movingSecs = 0;
    maxSpeedKmh = 0;
    elevationGainM = 0;
    currentSpeedKmh = 0;
    _elevRef = null;
    points.clear();
  }

  void addFix(GpsFix fix) {
    final speedKnown = fix.hasSpeed;
    final v = speedKnown ? fix.speedMps! : 0.0;

    if (!fix.accuracyM.isFinite || fix.accuracyM > maxAccuracyM) {
      if (speedKnown) currentSpeedKmh = v * 3.6;
      return;
    }
    _lastGood = fix;
    final anchor = _anchor;
    if (!_recording || anchor == null) {
      currentSpeedKmh = v * 3.6;
      if (_recording) _accept(fix);
      return;
    }

    final d = haversineM(anchor.lat, anchor.lng, fix.lat, fix.lng);
    final dt = fix.time.difference(anchor.time).inMilliseconds / 1000.0;
    final implied = dt > 0 ? d / dt : 0.0;

    if (dt > 0 && implied * 3.6 > glitchSpeedKmh) {
      // Teleport. If several in a row agree with each other, the anchor was
      // the bad fix: re-anchor without crediting the jump.
      _rejectedJumps.add(fix);
      if (_rejectedJumps.length >= 3 && _jumpsAgree()) {
        _rejectedJumps.clear();
        _accept(fix);
      }
      return;
    }
    _rejectedJumps.clear();

    // Doppler says we're standing still: any apparent movement is wander.
    if (speedKnown &&
        v < _stoppedMps &&
        (!anchor.hasSpeed || anchor.speedMps! < _stoppedMps)) {
      currentSpeedKmh = 0;
      return;
    }

    final moving = speedKnown && v >= _movingMps;
    final threshold = moving
        ? minStepM
        : math.max(minStepM, anchor.accuracyM + fix.accuracyM);
    if (d < threshold) {
      currentSpeedKmh = v * 3.6;
      return;
    }

    var segment = d;
    if (speedKnown && anchor.hasSpeed && dt > 0 && dt <= _maxDopplerGapSecs) {
      final doppler = (anchor.speedMps! + v) / 2 * dt;
      // Guard against a bogus speed reading disagreeing with the positions.
      if ((doppler - d).abs() <= math.max(10, d * 0.5)) segment = doppler;
    }

    distanceM += segment;
    movingSecs += math.min(dt, segment / movingSpeedMps);
    currentSpeedKmh = speedKnown ? v * 3.6 : implied * 3.6;
    final segmentKmh = speedKnown ? v * 3.6 : (dt >= 1 ? implied * 3.6 : 0.0);
    if (segmentKmh <= glitchSpeedKmh) {
      maxSpeedKmh = math.max(maxSpeedKmh, segmentKmh);
    }
    _accept(fix);
  }

  /// Commits the last sub-threshold stretch, if it looks like riding rather
  /// than a parked phone's wander.
  void _flushTail() {
    final anchor = _anchor;
    final last = _lastGood;
    if (anchor == null || last == null || identical(anchor, last)) return;
    final d = haversineM(anchor.lat, anchor.lng, last.lat, last.lng);
    final dt = last.time.difference(anchor.time).inMilliseconds / 1000.0;
    if (dt <= 0 || d < minStepM) return;
    final mps = d / dt;
    if (mps < movingSpeedMps || mps * 3.6 > glitchSpeedKmh) return;
    distanceM += d;
    movingSecs += dt;
    _accept(last);
  }

  bool _jumpsAgree() {
    for (var i = 1; i < _rejectedJumps.length; i++) {
      final a = _rejectedJumps[i - 1];
      final b = _rejectedJumps[i];
      final dt = b.time.difference(a.time).inMilliseconds / 1000.0;
      final d = haversineM(a.lat, a.lng, b.lat, b.lng);
      if (dt > 0 && d / dt * 3.6 > glitchSpeedKmh) return false;
    }
    return true;
  }

  void _accept(GpsFix fix) {
    _anchor = fix;
    _trackClimb(fix);
    points.add(TrackPoint(
      lat: fix.lat,
      lng: fix.lng,
      t: fix.time.toUtc(),
      elev: fix.altitudeM,
      accuracy: fix.accuracyM,
    ));
  }

  void _trackClimb(GpsFix fix) {
    final alt = fix.altitudeM;
    if (alt == null || !alt.isFinite) return;
    final altAcc = fix.altitudeAccuracyM;
    if (altAcc != null && altAcc > 20) return;
    final ref = _elevRef;
    if (ref == null) {
      _elevRef = alt;
    } else if (alt - ref >= climbThresholdM) {
      elevationGainM += alt - ref;
      _elevRef = alt;
    } else if (ref - alt >= climbThresholdM) {
      _elevRef = alt;
    }
  }
}
