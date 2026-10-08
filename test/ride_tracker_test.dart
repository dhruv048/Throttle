import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:throttle/services/ride_tracker.dart';

const _mPerDegLat = 111320.0;

/// Synthetic GPS stream: rides north from Kathmandu, one fix per second.
class _Sim {
  _Sim({int seed = 42}) : _rnd = math.Random(seed);

  final math.Random _rnd;
  final t0 = DateTime.utc(2026, 10, 9, 6);
  double northM = 0;
  double alt = 1300;
  int sec = 0;
  double _driftN = 0;
  double _driftE = 0;

  double _noise(double m) => (_rnd.nextDouble() * 2 - 1) * m;

  GpsFix fix({
    double speed = 0,
    double jitterM = 0,
    double accuracy = 5,
    double? reportedSpeed,
    bool noSpeed = false,
    double driftM = 0,
  }) {
    // Real stationary error drifts slowly rather than jumping every second.
    _driftN = (_driftN + _noise(driftM * 0.3)).clamp(-driftM, driftM);
    _driftE = (_driftE + _noise(driftM * 0.3)).clamp(-driftM, driftM);
    northM += speed;
    sec += 1;
    return GpsFix(
      lat: 27.7 + (northM + _driftN + _noise(jitterM)) / _mPerDegLat,
      lng: 85.3 +
          (_driftE + _noise(jitterM)) /
              (_mPerDegLat * math.cos(27.7 * math.pi / 180)),
      time: t0.add(Duration(seconds: sec)),
      accuracyM: accuracy,
      // Android reports 0.0 with no speed accuracy when it has no estimate.
      speedMps: noSpeed ? 0 : (reportedSpeed ?? speed),
      speedAccuracyMps: noSpeed ? 0 : 0.3,
      altitudeM: alt + _noise(1.5),
    );
  }
}

void main() {
  test('steady ride: distance within 1% of truth', () {
    final sim = _Sim();
    final tracker = RideTracker()..start();
    for (var i = 0; i < 600; i++) {
      tracker.addFix(sim.fix(speed: 15, jitterM: 3));
    }
    expect(tracker.distanceM, closeTo(sim.northM, sim.northM * 0.01));
    expect(tracker.movingSecs, closeTo(600, 5));
    expect(tracker.maxSpeedKmh, closeTo(54, 0.5));
  });

  test('steady ride without Doppler speed: within 2% of truth', () {
    final sim = _Sim();
    final tracker = RideTracker()..start();
    for (var i = 0; i < 600; i++) {
      tracker.addFix(sim.fix(speed: 15, jitterM: 1.5, noSpeed: true));
    }
    expect(tracker.distanceM, closeTo(sim.northM, sim.northM * 0.02));
  });

  test('parked, no Doppler speed, realistic drift: < 30 m', () {
    final sim = _Sim();
    final tracker = RideTracker()..start();
    for (var i = 0; i < 1800; i++) {
      tracker
          .addFix(sim.fix(driftM: 8, jitterM: 1, accuracy: 8, noSpeed: true));
    }
    tracker.pause();
    expect(tracker.distanceM, lessThan(30));
  });

  test('parked, no Doppler speed, harsh white noise: bounded', () {
    final sim = _Sim();
    final tracker = RideTracker()..start();
    for (var i = 0; i < 600; i++) {
      tracker.addFix(sim.fix(jitterM: 8, accuracy: 10, noSpeed: true));
    }
    // Old fix-to-fix summing gave ~2.5 km here.
    expect(tracker.distanceM, lessThan(100));
  });

  test('parked with GPS wander adds (almost) nothing', () {
    final sim = _Sim();
    final tracker = RideTracker()..start();
    var naive = 0.0;
    GpsFix? prev;
    for (var i = 0; i < 600; i++) {
      final f = sim.fix(jitterM: 8, accuracy: 10);
      if (prev != null) naive += haversineM(prev.lat, prev.lng, f.lat, f.lng);
      prev = f;
      tracker.addFix(f);
    }
    expect(naive, greaterThan(2000), reason: 'the old fix-to-fix sum');
    expect(tracker.distanceM, lessThan(30));
    expect(tracker.movingSecs, lessThan(30));
  });

  test('teleport glitch is ignored', () {
    final sim = _Sim();
    final tracker = RideTracker()..start();
    for (var i = 0; i < 60; i++) {
      tracker.addFix(sim.fix(speed: 15));
    }
    final good = sim.fix(speed: 15);
    tracker.addFix(GpsFix(
      lat: good.lat + 2000 / _mPerDegLat,
      lng: good.lng,
      time: good.time,
      accuracyM: 5,
    ));
    for (var i = 0; i < 60; i++) {
      tracker.addFix(sim.fix(speed: 15));
    }
    expect(tracker.distanceM, closeTo(sim.northM, 30));
  });

  test('bad first fix: re-anchors after consistent fixes', () {
    final sim = _Sim();
    final tracker = RideTracker()..start();
    final first = sim.fix(speed: 10);
    tracker.addFix(GpsFix(
      lat: first.lat + 5000 / _mPerDegLat,
      lng: first.lng,
      time: first.time,
    ));
    for (var i = 0; i < 120; i++) {
      tracker.addFix(sim.fix(speed: 10));
    }
    // Loses only the few seconds needed to detect the bad anchor.
    expect(tracker.distanceM, closeTo(1200, 60));
  });

  test('inaccurate fixes are skipped but distance resumes from the anchor', () {
    final sim = _Sim();
    final tracker = RideTracker()..start();
    for (var i = 0; i < 100; i++) {
      tracker.addFix(sim.fix(speed: 12, accuracy: i >= 30 && i < 60 ? 80 : 5));
    }
    expect(tracker.distanceM, closeTo(1200, 15));
  });

  test('movement while paused is not counted', () {
    final sim = _Sim();
    final tracker = RideTracker()..start();
    for (var i = 0; i < 100; i++) {
      tracker.addFix(sim.fix(speed: 10));
    }
    tracker.pause();
    for (var i = 0; i < 100; i++) {
      tracker.addFix(sim.fix(speed: 10));
    }
    tracker.start(now: sim.t0.add(Duration(seconds: sim.sec)));
    for (var i = 0; i < 100; i++) {
      tracker.addFix(sim.fix(speed: 10));
    }
    expect(tracker.distanceM, closeTo(2000, 30));
  });

  test('stop at a junction is excluded from moving time', () {
    final sim = _Sim();
    final tracker = RideTracker()..start();
    for (var i = 0; i < 300; i++) {
      tracker.addFix(sim.fix(speed: 12));
    }
    for (var i = 0; i < 300; i++) {
      tracker.addFix(sim.fix(jitterM: 4, accuracy: 6));
    }
    for (var i = 0; i < 300; i++) {
      tracker.addFix(sim.fix(speed: 12));
    }
    expect(tracker.movingSecs, closeTo(600, 20));
    expect(tracker.avgSpeedKmh, closeTo(43.2, 1.5));
  });

  test('slow traffic crawl still counts', () {
    final sim = _Sim();
    final tracker = RideTracker()..start();
    for (var i = 0; i < 200; i++) {
      tracker.addFix(sim.fix(speed: 1.5, jitterM: 1, accuracy: 8));
    }
    tracker.pause(); // finish flushes the last sub-threshold stretch
    expect(tracker.distanceM, closeTo(300, 12));
  });

  test('climb counted, altitude noise ignored', () {
    final sim = _Sim();
    final tracker = RideTracker()..start();
    for (var i = 0; i < 300; i++) {
      tracker.addFix(sim.fix(speed: 10));
    }
    expect(tracker.elevationGainM, lessThan(4));
    for (var i = 0; i < 300; i++) {
      sim.alt += 0.5;
      tracker.addFix(sim.fix(speed: 10));
    }
    expect(tracker.elevationGainM, closeTo(150, 8));
  });

  test('track points carry time, elevation and accuracy', () {
    final sim = _Sim();
    final tracker = RideTracker()..start();
    for (var i = 0; i < 10; i++) {
      tracker.addFix(sim.fix(speed: 15));
    }
    expect(tracker.points, hasLength(10));
    expect(tracker.points.first.t, isNotNull);
    expect(tracker.points.first.elev, isNotNull);
    expect(tracker.points.first.accuracy, 5);
  });
}
