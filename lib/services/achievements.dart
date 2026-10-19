import '../format.dart';
import '../models/models.dart';
import '../units.dart';

/// What a rider has done on Throttle, all told: what badges are judged on.
/// Made from their rides ([RiderTotals.of]) or, for the leaderboard, by the
/// server ([RiderTotals.fromJson], `rider_leaderboard()`).
class RiderTotals {
  const RiderTotals({
    this.rides = 0,
    this.km = 0,
    this.longestKm = 0,
    this.climbM = 0,
    this.biggestClimbM = 0,
    this.places = 0,
    this.longestSecs = 0,
  });

  /// Rides, i.e. flags planted.
  final int rides;
  final double km;
  final double longestKm;
  final double climbM;

  /// The most climbed in one ride.
  final double biggestClimbM;

  /// Different places reached (rides' flags, by name).
  final int places;

  /// The longest time in the saddle on one ride.
  final int longestSecs;

  static const zero = RiderTotals();

  factory RiderTotals.of(Iterable<RideRecord> rides) {
    var n = 0, km = 0.0, longest = 0.0, climb = 0.0, biggest = 0.0;
    var secs = 0;
    final places = <String>{};
    for (final r in rides) {
      n++;
      km += r.distanceKm;
      climb += r.elevationM;
      if (r.distanceKm > longest) longest = r.distanceKm;
      if (r.elevationM > biggest) biggest = r.elevationM;
      if (r.movingTimeSecs > secs) secs = r.movingTimeSecs;
      if (r.endPlace != null) places.add(r.endPlace!);
    }
    return RiderTotals(
      rides: n,
      km: km,
      longestKm: longest,
      climbM: climb,
      biggestClimbM: biggest,
      places: places.length,
      longestSecs: secs,
    );
  }

  factory RiderTotals.fromJson(Map<String, dynamic> json) {
    double d(String key) => (json[key] as num?)?.toDouble() ?? 0;
    return RiderTotals(
      rides: (json['rides'] as num?)?.toInt() ?? 0,
      km: d('total_km'),
      longestKm: d('longest_km'),
      climbM: d('climb_m'),
      biggestClimbM: d('biggest_climb_m'),
      places: (json['places'] as num?)?.toInt() ?? 0,
      longestSecs: (json['longest_secs'] as num?)?.toInt() ?? 0,
    );
  }
}

enum BadgeKind { flags, distance, longRide, climb, explorer, saddle }

/// Something to earn: a number to reach in one of [RiderTotals]' measures.
class RideBadge {
  const RideBadge(
      this.id, this.kind, this.title, this.description, this.target, this.unit);

  final String id;
  final BadgeKind kind;
  final String title;
  final String description;
  final double target;

  /// How progress towards it reads ("km", "rides"…).
  final String unit;

  /// Where the rider is towards it, in [unit]s.
  double value(RiderTotals t) => switch (kind) {
        BadgeKind.flags => t.rides.toDouble(),
        BadgeKind.distance => t.km,
        BadgeKind.longRide => t.longestKm,
        BadgeKind.climb => id == 'pass_rider' ? t.biggestClimbM : t.climbM,
        BadgeKind.explorer => t.places.toDouble(),
        BadgeKind.saddle => t.longestSecs / 3600,
      };

  bool earnedBy(RiderTotals t) => value(t) >= target;

  /// 0 → 1.
  double progress(RiderTotals t) => (value(t) / target).clamp(0.0, 1.0);

  /// "640 / 1,000 km"
  String progressText(RiderTotals t) {
    final v = value(t).clamp(0, target);
    final shown = unit == 'h' ? v.toStringAsFixed(1) : formatNumber(v.floor());
    final goal =
        unit == 'h' ? target.toStringAsFixed(0) : formatNumber(target.round());
    return '$shown / $goal $unit';
  }

  /// Every badge, easiest of each kind first.
  static const all = [
    RideBadge('first_flag', BadgeKind.flags, 'First flag',
        'Plant your first flag: finish a ride', 1, 'rides'),
    RideBadge(
        'regular', BadgeKind.flags, 'Regular', 'Plant 10 flags', 10, 'rides'),
    RideBadge('collector', BadgeKind.flags, 'Flag collector', 'Plant 25 flags',
        25, 'rides'),
    RideBadge('centurion', BadgeKind.flags, 'Centurion', 'Plant 100 flags', 100,
        'rides'),
    RideBadge('km_100', BadgeKind.distance, '100 km club',
        'Ride 100 km on Throttle', 100, 'km'),
    RideBadge('km_1000', BadgeKind.distance, '1,000 km club',
        'Ride 1,000 km on Throttle', 1000, 'km'),
    RideBadge('km_10000', BadgeKind.distance, '10,000 km club',
        'Ride 10,000 km on Throttle', 10000, 'km'),
    RideBadge('half_century', BadgeKind.longRide, 'Half century',
        'Ride 50 km in one go', 50, 'km'),
    RideBadge('century', BadgeKind.longRide, 'Century', 'Ride 100 km in one go',
        100, 'km'),
    RideBadge('double_century', BadgeKind.longRide, 'Double century',
        'Ride 200 km in one go', 200, 'km'),
    RideBadge('hill_climber', BadgeKind.climb, 'Hill climber',
        'Climb 1,000 m, all told', 1000, 'm'),
    RideBadge('pass_rider', BadgeKind.climb, 'Pass rider',
        'Climb 1,000 m in one ride', 1000, 'm'),
    RideBadge('everest', BadgeKind.climb, 'Everest',
        'Climb 8,849 m, all told: the height of Everest', 8849, 'm'),
    RideBadge('explorer', BadgeKind.explorer, 'Explorer',
        'Reach 5 different places', 5, 'places'),
    RideBadge('wanderer', BadgeKind.explorer, 'Wanderer',
        'Reach 15 different places', 15, 'places'),
    RideBadge('saddle_time', BadgeKind.saddle, 'Saddle time',
        'Ride 3 hours in one go', 3, 'h'),
  ];

  static List<RideBadge> earned(RiderTotals t) => [
        for (final b in all)
          if (b.earnedBy(t)) b
      ];
}

enum AchievementKind { badge, longest, fastest, climb }

/// Something a ride earned: a badge, or a personal best.
class Achievement {
  const Achievement(this.kind, this.title, this.detail, {this.badge});

  final AchievementKind kind;
  final String title;
  final String detail;

  /// The badge, for [AchievementKind.badge].
  final RideBadge? badge;
}

/// What a just-saved ride means for the rider: which flag it is, and what it
/// earned compared with every ride before it.
class RideAchievements {
  const RideAchievements(
      {this.flagNumber, this.totalKm, this.earned = const []});

  /// How many flags the rider has planted, this one included. Null when
  /// their earlier rides couldn't be loaded (offline).
  final int? flagNumber;

  /// Everything they've ridden on Throttle, this ride included.
  final double? totalKm;
  final List<Achievement> earned;

  /// [ride] against [before], every other ride the rider has saved. Null
  /// [before] (unknown) earns nothing, rather than a false "first flag".
  /// Personal bests read in [units].
  factory RideAchievements.compute(
      PendingRide ride, Iterable<RideRecord>? before,
      {Units units = Units.metric}) {
    if (before == null) return const RideAchievements();
    final earlier = before.toList();
    final then = RiderTotals.of(earlier);
    final now = RiderTotals.of([...earlier, ride.toRecord()]);
    final earned = <Achievement>[
      for (final b in RideBadge.all)
        if (b.earnedBy(now) && !b.earnedBy(then))
          Achievement(AchievementKind.badge, b.title, b.description, badge: b),
    ];

    if (earlier.isNotEmpty) {
      // Rounding noise isn't a record.
      if (ride.distanceKm >= 1 && ride.distanceKm > then.longestKm + 0.05) {
        earned.add(Achievement(
            AchievementKind.longest,
            'Longest ride yet',
            '${units.fixed(ride.distanceKm, 1)} ${units.distanceUnit}, '
                '${units.fixed(ride.distanceKm - then.longestKm, 1)} '
                '${units.distanceUnit} past your best'));
      }
      final fastest =
          earlier.map((r) => r.maxSpeedKmh).reduce((a, b) => a > b ? a : b);
      if (fastest > 0 && ride.maxSpeedKmh.round() > fastest.round()) {
        earned.add(Achievement(
            AchievementKind.fastest,
            'New top speed',
            '${units.speedText(ride.maxSpeedKmh)} top speed, up from '
                '${units.speedText(fastest)}'));
      }
      if (ride.elevationM >= 100 &&
          ride.elevationM.round() > then.biggestClimbM.round()) {
        earned.add(Achievement(AchievementKind.climb, 'Biggest climb yet',
            '${formatNumber(ride.elevationM.round())} m up in one ride'));
      }
    }
    return RideAchievements(
        flagNumber: now.rides, totalKm: now.km, earned: earned);
  }
}

/// "1st", "2nd", "3rd", "11th", "22nd".
String ordinal(int n) {
  final teens = n % 100 >= 11 && n % 100 <= 13;
  final suffix = teens
      ? 'th'
      : switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
  return '$n$suffix';
}

/// A rider on the leaderboard: who they are and what they've done.
class RiderStanding {
  const RiderStanding(this.rider, this.totals);

  final Profile rider;
  final RiderTotals totals;

  factory RiderStanding.fromJson(Map<String, dynamic> json) =>
      RiderStanding(Profile.fromJson(json), RiderTotals.fromJson(json));

  List<RideBadge> get badges => RideBadge.earned(totals);
}
