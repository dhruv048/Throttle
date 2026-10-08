import 'package:flutter_test/flutter_test.dart';
import 'package:throttle/data.dart';
import 'package:throttle/models/models.dart';

void main() {
  group('RideVisibility', () {
    test('parses from label correctly', () {
      expect(RideVisibility.fromLabel('Public'), RideVisibility.public);
      expect(RideVisibility.fromLabel('public'), RideVisibility.public);
      expect(RideVisibility.fromLabel('Private'), RideVisibility.private);
      expect(RideVisibility.fromLabel('Followers'), RideVisibility.followers);
      expect(RideVisibility.fromLabel('unknown'), RideVisibility.followers);
    });

    test('parses from db correctly', () {
      expect(RideVisibility.fromDb('public'), RideVisibility.public);
      expect(RideVisibility.fromDb('followers'), RideVisibility.followers);
      expect(RideVisibility.fromDb('private'), RideVisibility.private);
      expect(RideVisibility.fromDb(null), RideVisibility.followers);
    });
  });

  group('TrackPoint', () {
    test('JSON round-trip', () {
      final now = DateTime.now();
      final point = TrackPoint(
        lat: 27.7172,
        lng: 85.3240,
        elev: 1400.5,
        t: now,
        accuracy: 4.2,
      );

      final json = point.toJson();
      final restored = TrackPoint.fromJson(json);

      expect(restored.lat, closeTo(27.7172, 0.0001));
      expect(restored.lng, closeTo(85.3240, 0.0001));
      expect(restored.elev, 1400.5);
      expect(restored.accuracy, 4.2);
    });
  });

  group('Profile', () {
    test('initials computation', () {
      const p1 = Profile(id: '1', displayName: 'Sam Goyal');
      expect(p1.initials, 'SG');

      const p2 = Profile(id: '2', username: 'rider99');
      expect(p2.initials, 'RI');

      const p3 = Profile(id: '3');
      expect(p3.initials, '?');
    });

    test('JSON round-trip', () {
      const profile = Profile(
        id: 'user-123',
        username: 'kathmandu_rider',
        displayName: 'Rider K',
        city: 'Kathmandu',
        bio: 'Two wheels only',
        onboardingCompleted: true,
      );

      final json = profile.toJson();
      final restored = Profile.fromJson(json);

      expect(restored.id, 'user-123');
      expect(restored.username, 'kathmandu_rider');
      expect(restored.displayName, 'Rider K');
      expect(restored.city, 'Kathmandu');
      expect(restored.bio, 'Two wheels only');
      expect(restored.onboardingCompleted, true);
    });
  });

  group('PendingRide', () {
    test('JSON round-trip with track points and userId', () {
      final now = DateTime.now();
      final pending = PendingRide(
        localId: 'local-abc-123',
        userId: 'usr-999',
        title: 'Morning Cruise',
        visibility: RideVisibility.followers,
        distanceKm: 24.5,
        movingTimeSecs: 2400,
        avgSpeedKmh: 36.75,
        maxSpeedKmh: 65.0,
        bikeName: 'Yamaha MT-15',
        bikeId: 'bike-uuid-456',
        points: [
          TrackPoint(lat: 27.71, lng: 85.32, t: now),
          TrackPoint(
              lat: 27.72, lng: 85.33, t: now.add(const Duration(seconds: 10))),
        ],
        createdAt: now,
        startedAt: now.subtract(const Duration(minutes: 40)),
        endedAt: now,
        synced: false,
      );

      final json = pending.toJson();
      final restored = PendingRide.fromJson(json);

      expect(restored.localId, 'local-abc-123');
      expect(restored.userId, 'usr-999');
      expect(restored.title, 'Morning Cruise');
      expect(restored.visibility, RideVisibility.followers);
      expect(restored.distanceKm, 24.5);
      expect(restored.movingTimeSecs, 2400);
      expect(restored.avgSpeedKmh, 36.75);
      expect(restored.maxSpeedKmh, 65.0);
      expect(restored.bikeName, 'Yamaha MT-15');
      expect(restored.bikeId, 'bike-uuid-456');
      expect(restored.points.length, 2);
      expect(restored.synced, false);
      expect(restored.remoteId, isNull);
    });
  });

  group('FeedItem', () {
    final row = {
      'id': 'ride-1',
      'user_id': 'u1',
      'title': 'Nagarkot sunrise run',
      'visibility': 'public',
      'distance_km': 22.4,
      'moving_time_secs': 3120,
      'avg_speed_kmh': 25.8,
      'max_speed_kmh': 64,
      'elevation_m': 700,
      'kudos_count': 4,
      'comments_count': 2,
      'start_place': 'Bhaktapur',
      'end_place': 'Nagarkot',
      'ended_at': '2026-10-08T05:00:00Z',
      'rider': {
        'id': 'u1',
        'username': 'priya_g',
        'display_name': 'Priya Gurung'
      },
      'bike': {'name': 'KTM 390 Duke'},
      'track': {
        'points': [
          {'lat': 27.67, 'lng': 85.42},
          {'lat': 27.71, 'lng': 85.52},
        ],
      },
    };

    test('parses embedded rider, bike and track', () {
      final item = FeedItem.fromJson(row, likedByMe: true);
      expect(item.ride.title, 'Nagarkot sunrise run');
      expect(item.ride.startPlace, 'Bhaktapur');
      expect(item.ride.endPlace, 'Nagarkot');
      expect(item.rider.initials, 'PG');
      expect(item.bikeName, 'KTM 390 Duke');
      expect(item.points, hasLength(2));
      expect(item.likedByMe, isTrue);
    });

    test('tolerates missing embeds and list-shaped track', () {
      final item = FeedItem.fromJson({
        ...row,
        'rider': null,
        'bike': null,
        'track': <dynamic>[],
      });
      expect(item.rider.id, 'u1');
      expect(item.bikeName, isNull);
      expect(item.points, isEmpty);
    });

    test('copyWith updates kudos optimistically', () {
      final item = FeedItem.fromJson(row);
      final liked = item.copyWith(likedByMe: true, kudosCount: 5);
      expect(liked.likedByMe, isTrue);
      expect(liked.ride.kudosCount, 5);
      expect(liked.ride.endPlace, 'Nagarkot');
    });
  });

  group('formatting', () {
    test('formatDuration', () {
      expect(formatDuration(3120), '52m');
      expect(formatDuration(13800), '3h 50m');
    });

    test('timeAgo', () {
      final now = DateTime(2026, 10, 8, 12);
      expect(
          timeAgo(now.subtract(const Duration(hours: 2)), now: now), '2h ago');
      expect(timeAgo(now.subtract(const Duration(hours: 30)), now: now),
          'Yesterday');
      expect(
          timeAgo(now.subtract(const Duration(days: 3)), now: now), '3d ago');
    });
  });

  group('RideStats', () {
    RideRecord ride(DateTime at, double km,
            {int secs = 3600, double elev = 100}) =>
        RideRecord(
          id: '$at',
          userId: 'u',
          title: 'r',
          visibility: RideVisibility.public,
          distanceKm: km,
          movingTimeSecs: secs,
          avgSpeedKmh: 0,
          maxSpeedKmh: 0,
          elevationM: elev,
          startedAt: at,
        );

    // Thursday 8 Oct 2026; this week starts Monday 5 Oct.
    final now = DateTime(2026, 10, 8, 12);

    test('year totals, month, and Monday-based weeks', () {
      final stats = RideStats.compute([
        ride(DateTime(2026, 10, 8, 7), 10.25), // today
        ride(DateTime(2026, 10, 5, 0, 30), 5), // Monday, this week
        ride(DateTime(2026, 10, 4, 23, 59), 7), // Sunday, last week
        ride(DateTime(2026, 9, 30), 20), // last week, previous month
        ride(DateTime(2026, 8, 17), 40), // Monday 17 Aug: oldest bar
        ride(DateTime(2026, 8, 16, 23), 3), // just before the chart
        ride(DateTime(2025, 12, 31), 100), // last year
      ], now: now);

      expect(stats.rides, 6);
      expect(stats.km, closeTo(85.25, 1e-9));
      expect(stats.elevationM, 600);
      expect(stats.movingSecs, 6 * 3600);
      expect(stats.monthKm, closeTo(22.25, 1e-9));
      expect(stats.weeklyKm, hasLength(8));
      expect(stats.weeklyKm.last, closeTo(15.25, 1e-9));
      expect(stats.weeklyKm[6], closeTo(27, 1e-9));
      expect(stats.weeklyKm.first, closeTo(40, 1e-9));
    });

    test('rides without a date are ignored; empty is all zeros', () {
      final stats = RideStats.compute([
        RideRecord(
          id: 'x',
          userId: 'u',
          title: 'r',
          visibility: RideVisibility.public,
          distanceKm: 5,
          movingTimeSecs: 1,
          avgSpeedKmh: 0,
          maxSpeedKmh: 0,
        ),
      ], now: now);
      expect(stats.rides, 0);
      expect(stats.weeklyKm.every((w) => w == 0), isTrue);
    });

    test('pending rides convert to records for stats', () {
      final p = PendingRide(
        localId: 'local-1',
        userId: 'u',
        title: 'Offline ride',
        visibility: RideVisibility.private,
        distanceKm: 12.34,
        movingTimeSecs: 1800,
        avgSpeedKmh: 24.7,
        maxSpeedKmh: 60,
        elevationM: 210,
        bikeName: 'S1000RR',
        points: const [],
        createdAt: DateTime(2026, 10, 8, 9),
        startedAt: DateTime(2026, 10, 8, 8, 30),
      );
      final restored = PendingRide.fromJson(p.toJson());
      expect(restored.elevationM, 210);
      final r = restored.toRecord();
      expect(r.localId, 'local-1');
      expect(r.rodeAt, DateTime(2026, 10, 8, 8, 30));
      expect(
          RideStats.compute([r], now: now).weeklyKm.last, closeTo(12.34, 1e-9));
    });
  });

  test('formatDistance keeps one exact decimal', () {
    expect(formatDistance(0), '0.0');
    expect(formatDistance(12.345), '12.3');
    expect(formatDistance(1234.56), '1,234.6');
    expect(formatDistance(9.96), '10.0');
  });

  test('BikeRecord parses ridden_km', () {
    final b = BikeRecord.fromJson({
      'id': 'b',
      'user_id': 'u',
      'name': 'MT-15',
      'odometer_km': 5432.1,
      'ridden_km': 412.3,
    });
    expect(b.riddenKm, 412.3);
  });
}
