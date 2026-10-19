import 'package:flutter_test/flutter_test.dart';
import 'package:throttle/models/models.dart';
import 'package:throttle/services/achievements.dart';
import 'package:throttle/units.dart';

PendingRide _ride({double km = 20, double top = 80}) => PendingRide(
      localId: 'new',
      title: PendingRide.defaultTitle(km),
      visibility: RideVisibility.public,
      distanceKm: km,
      movingTimeSecs: 1800,
      avgSpeedKmh: 40,
      maxSpeedKmh: top,
      bikeName: 'KTM 390 Duke',
      points: const [],
      createdAt: DateTime(2026, 10, 16),
    );

RideRecord _before(int i, {double km = 10, double top = 70}) => RideRecord(
      id: 'r$i',
      userId: 'me',
      title: 'Ride $i',
      visibility: RideVisibility.public,
      distanceKm: km,
      movingTimeSecs: 1200,
      avgSpeedKmh: 30,
      maxSpeedKmh: top,
    );

String _titles(RideAchievements a) => a.earned.map((e) => e.title).join(', ');

void main() {
  group('a ride\'s flag', () {
    test('stands where the ride reached furthest from its start', () {
      // Out 3 points north, then back to the start.
      const loop = [
        TrackPoint(lat: 27.70, lng: 85.30),
        TrackPoint(lat: 27.72, lng: 85.30),
        TrackPoint(lat: 27.74, lng: 85.31),
        TrackPoint(lat: 27.72, lng: 85.30),
        TrackPoint(lat: 27.70, lng: 85.30),
      ];
      final flag = flagPoint(loop)!;
      expect((flag.lat, flag.lng), (27.74, 85.31));

      // One way: the destination.
      expect(flagPoint(loop.take(3).toList())!.lat, 27.74);
      expect(flagPoint(const []), isNull);
    });

    test('rides still on the phone carry theirs', () {
      final ride = PendingRide.fromJson({
        ..._ride().toJson(),
        'points': [
          {'lat': 27.7, 'lng': 85.3},
          {'lat': 27.8, 'lng': 85.4},
        ],
      });
      final flag = RideFlag.fromRecord(ride.toRecord(), pending: true)!;
      expect((flag.lat, flag.lng), (27.8, 85.4));
      expect(flag.pending, isTrue);
    });
  });

  group('what a ride earns', () {
    test('the first is a first flag', () {
      final a = RideAchievements.compute(_ride(), const []);
      expect(a.flagNumber, 1);
      expect(_titles(a), 'First flag');
      expect(a.earned.single.badge!.id, 'first_flag');
    });

    test('personal bests, against every earlier ride', () {
      final a = RideAchievements.compute(_ride(km: 42.5, top: 112), [
        _before(1, km: 30, top: 95),
        _before(2, km: 12, top: 101),
      ]);
      expect(a.flagNumber, 3);
      expect(_titles(a), 'Longest ride yet, New top speed');
      expect(a.earned[0].detail, '42.5 km, 12.5 km past your best');
      expect(a.earned[1].detail, '112 km/h top speed, up from 101 km/h');

      // In the rider's units.
      final miles = RideAchievements.compute(
          _ride(km: 42.5, top: 112), [_before(1, km: 30, top: 95)],
          units: Units.imperial);
      expect(miles.earned[0].detail, '26.4 mi, 7.8 mi past your best');
      expect(miles.earned[1].detail, '70 mph top speed, up from 59 mph');
    });

    test('badges the ride tipped over', () {
      final a = RideAchievements.compute(
          _ride(km: 10, top: 60), [for (var i = 1; i <= 9; i++) _before(i)]);
      // 10 rides, 9 × 10 km before, 100 km after; not longer than the best.
      expect(_titles(a), 'Regular, 100 km club');
      expect(a.totalKm, 100);

      final century =
          RideAchievements.compute(_ride(km: 104, top: 60), [_before(1)]);
      expect(_titles(century),
          '100 km club, Half century, Century, Longest ride yet');
    });

    test('nothing claimed when earlier rides aren\'t known (offline)', () {
      final a = RideAchievements.compute(_ride(), null);
      expect(a.flagNumber, isNull);
      expect(a.earned, isEmpty);
    });

    test('ordinals', () {
      expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 101, 111].map(ordinal), [
        '1st',
        '2nd',
        '3rd',
        '4th',
        '11th',
        '12th',
        '13th',
        '21st',
        '22nd',
        '101st',
        '111th'
      ]);
    });
  });

  test('a ride\'s title, words and photos survive the trip to the phone', () {
    final ride = _ride().copyWith(
      title: 'Sunrise loop',
      journal: 'Fog lifting.',
      bikeId: 'b2',
      bikeName: 'Himalayan 450',
      media: const [
        PendingMedia(id: 'p1', extension: 'jpg', lat: 27.7, lng: 85.3),
        PendingMedia(id: 'v1', extension: 'mov', uploaded: true),
      ],
    );
    final back = PendingRide.fromJson(ride.toJson());
    expect(back.title, 'Sunrise loop');
    expect(back.journal, 'Fog lifting.');
    expect(back.bikeId, 'b2');
    expect(back.bikeName, 'Himalayan 450');
    expect(back.media.map((m) => (m.id, m.placed, m.isVideo, m.uploaded)),
        [('p1', true, false, false), ('v1', false, true, true)]);
    // Blank words are no words.
    expect(ride.copyWith(journal: '  ').journal, isNull);
  });

  group('badges', () {
    RideRecord ride(double km,
            {double climb = 0, int secs = 1800, String? place}) =>
        RideRecord(
          id: 'r$km$place',
          userId: 'me',
          title: 'Ride',
          visibility: RideVisibility.public,
          distanceKm: km,
          movingTimeSecs: secs,
          avgSpeedKmh: 30,
          maxSpeedKmh: 60,
          elevationM: climb,
          endPlace: place,
        );

    test('totals from a rider\'s rides', () {
      final t = RiderTotals.of([
        ride(60, climb: 400, place: 'Nagarkot'),
        ride(120, climb: 1100, secs: 4 * 3600, place: 'Pokhara'),
        ride(20, place: 'Nagarkot'),
      ]);
      expect(t.rides, 3);
      expect(t.km, 200);
      expect(t.longestKm, 120);
      expect(t.climbM, 1500);
      expect(t.biggestClimbM, 1100);
      expect(t.places, 2);
      expect(t.longestSecs, 4 * 3600);
      expect(RideBadge.earned(t).map((b) => b.id), [
        'first_flag',
        'km_100',
        'half_century',
        'century',
        'hill_climber',
        'pass_rider',
        'saddle_time',
      ]);
    });

    test('progress towards one not earned yet', () {
      const t = RiderTotals(km: 640);
      final club = RideBadge.all.firstWhere((b) => b.id == 'km_1000');
      expect(club.earnedBy(t), isFalse);
      expect(club.progress(t), closeTo(0.64, 1e-9));
      expect(club.progressText(t), '640 / 1,000 km');
      final saddle = RideBadge.all.firstWhere((b) => b.id == 'saddle_time');
      expect(saddle.progressText(const RiderTotals(longestSecs: 5400)),
          '1.5 / 3 h');
    });

    test('the leaderboard\'s totals read the same way', () {
      final s = RiderStanding.fromJson({
        'id': 'mira',
        'display_name': 'Mira Rai',
        'rides': 12,
        'total_km': 1240.5,
        'longest_km': 210,
        'climb_m': 9100,
        'biggest_climb_m': 1300,
        'places': 6,
        'longest_secs': 20000,
      });
      expect(s.rider.displayName, 'Mira Rai');
      expect(s.badges.length, 12);
    });
  });
}
