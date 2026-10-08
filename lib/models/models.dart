enum RideVisibility {
  public,
  followers,
  private;

  static RideVisibility fromLabel(String label) {
    switch (label.toLowerCase()) {
      case 'public':
        return RideVisibility.public;
      case 'private':
        return RideVisibility.private;
      default:
        return RideVisibility.followers;
    }
  }

  String get dbValue => name;

  String get label {
    switch (this) {
      case RideVisibility.public:
        return 'Public';
      case RideVisibility.followers:
        return 'Followers';
      case RideVisibility.private:
        return 'Private';
    }
  }

  static RideVisibility fromDb(String? value) {
    return RideVisibility.values.firstWhere(
      (v) => v.name == value,
      orElse: () => RideVisibility.followers,
    );
  }
}

class TrackPoint {
  const TrackPoint({
    required this.lat,
    required this.lng,
    this.t,
    this.elev,
    this.accuracy,
  });

  final double lat;
  final double lng;
  final DateTime? t;
  final double? elev;
  final double? accuracy;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        if (t != null) 't': t!.toIso8601String(),
        if (elev != null) 'elev': elev,
        if (accuracy != null) 'accuracy': accuracy,
      };

  factory TrackPoint.fromJson(Map<String, dynamic> json) => TrackPoint(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        t: json['t'] != null ? DateTime.tryParse(json['t'] as String) : null,
        elev: (json['elev'] as num?)?.toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
      );
}

class Profile {
  const Profile({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.city,
    this.bio,
    this.onboardingCompleted = false,
  });

  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? city;
  final String? bio;
  final bool onboardingCompleted;

  String get initials {
    final raw = (displayName ?? username ?? '?').trim();
    final parts = raw.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return raw.substring(0, raw.length.clamp(0, 2)).toUpperCase();
  }

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        username: json['username'] as String?,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        city: json['city'] as String?,
        bio: json['bio'] as String?,
        onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'city': city,
        'bio': bio,
        'onboarding_completed': onboardingCompleted,
      };
}

class BikeRecord {
  const BikeRecord({
    required this.id,
    required this.userId,
    required this.name,
    this.make,
    this.model,
    this.year,
    this.odometerKm = 0,
    this.riddenKm = 0,
    this.isPrimary = false,
    this.photoUrl,
  });

  final String id;
  final String userId;
  final String name;
  final String? make;
  final String? model;
  final int? year;
  final double odometerKm;

  /// Distance recorded on rides with this bike (maintained by a DB trigger).
  final double riddenKm;
  final bool isPrimary;
  final String? photoUrl;

  factory BikeRecord.fromJson(Map<String, dynamic> json) => BikeRecord(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        name: json['name'] as String,
        make: json['make'] as String?,
        model: json['model'] as String?,
        year: json['year'] as int?,
        odometerKm: (json['odometer_km'] as num?)?.toDouble() ?? 0,
        riddenKm: (json['ridden_km'] as num?)?.toDouble() ?? 0,
        isPrimary: json['is_primary'] as bool? ?? false,
        photoUrl: json['photo_url'] as String?,
      );
}

class RideRecord {
  const RideRecord({
    required this.id,
    required this.userId,
    this.bikeId,
    required this.title,
    required this.visibility,
    required this.distanceKm,
    required this.movingTimeSecs,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    this.elevationM = 0,
    this.startedAt,
    this.endedAt,
    this.kudosCount = 0,
    this.commentsCount = 0,
    this.localId,
    this.startPlace,
    this.endPlace,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String? bikeId;
  final String title;
  final RideVisibility visibility;
  final double distanceKm;
  final int movingTimeSecs;
  final double avgSpeedKmh;
  final double maxSpeedKmh;
  final double elevationM;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int kudosCount;
  final int commentsCount;
  final String? localId;
  final String? startPlace;
  final String? endPlace;
  final DateTime? createdAt;

  /// When the ride happened, for grouping into weeks/months.
  DateTime? get rodeAt => startedAt ?? endedAt ?? createdAt;

  factory RideRecord.fromJson(Map<String, dynamic> json) => RideRecord(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        bikeId: json['bike_id'] as String?,
        title: json['title'] as String? ?? 'Ride',
        visibility: RideVisibility.fromDb(json['visibility'] as String?),
        distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
        movingTimeSecs: (json['moving_time_secs'] as num?)?.toInt() ?? 0,
        avgSpeedKmh: (json['avg_speed_kmh'] as num?)?.toDouble() ?? 0,
        maxSpeedKmh: (json['max_speed_kmh'] as num?)?.toDouble() ?? 0,
        elevationM: (json['elevation_m'] as num?)?.toDouble() ?? 0,
        startedAt: json['started_at'] != null
            ? DateTime.tryParse(json['started_at'] as String)
            : null,
        endedAt: json['ended_at'] != null
            ? DateTime.tryParse(json['ended_at'] as String)
            : null,
        kudosCount: json['kudos_count'] as int? ?? 0,
        commentsCount: json['comments_count'] as int? ?? 0,
        localId: json['local_id'] as String?,
        startPlace: json['start_place'] as String?,
        endPlace: json['end_place'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)
            : null,
      );
}

/// A ride as shown in the home feed: ride + rider + bike + GPS track.
class FeedItem {
  const FeedItem({
    required this.ride,
    required this.rider,
    this.bikeName,
    this.bikePhotoUrl,
    this.points = const [],
    this.likedByMe = false,
    this.pending = false,
  });

  final RideRecord ride;
  final Profile rider;
  final String? bikeName;
  final String? bikePhotoUrl;
  final List<TrackPoint> points;
  final bool likedByMe;

  /// Saved on this device, not uploaded yet.
  final bool pending;

  FeedItem copyWith({bool? likedByMe, int? kudosCount}) => FeedItem(
        ride: kudosCount == null
            ? ride
            : RideRecord(
                id: ride.id,
                userId: ride.userId,
                bikeId: ride.bikeId,
                title: ride.title,
                visibility: ride.visibility,
                distanceKm: ride.distanceKm,
                movingTimeSecs: ride.movingTimeSecs,
                avgSpeedKmh: ride.avgSpeedKmh,
                maxSpeedKmh: ride.maxSpeedKmh,
                elevationM: ride.elevationM,
                startedAt: ride.startedAt,
                endedAt: ride.endedAt,
                kudosCount: kudosCount,
                commentsCount: ride.commentsCount,
                localId: ride.localId,
                startPlace: ride.startPlace,
                endPlace: ride.endPlace,
                createdAt: ride.createdAt,
              ),
        rider: rider,
        bikeName: bikeName,
        bikePhotoUrl: bikePhotoUrl,
        points: points,
        likedByMe: likedByMe ?? this.likedByMe,
        pending: pending,
      );

  /// Parses a `rides` row with embedded `rider`, `bike` and `track`.
  factory FeedItem.fromJson(Map<String, dynamic> json,
      {bool likedByMe = false}) {
    final rider = json['rider'] as Map?;
    final bike = json['bike'] as Map?;
    final track = json['track'];
    // ride_tracks.ride_id is unique, so PostgREST embeds an object; tolerate a list.
    final trackRow =
        track is List ? (track.isEmpty ? null : track.first) : track;
    final rawPoints = (trackRow as Map?)?['points'] as List? ?? const [];
    return FeedItem(
      ride: RideRecord.fromJson(json),
      rider: rider != null
          ? Profile.fromJson(Map<String, dynamic>.from(rider))
          : Profile(id: json['user_id'] as String),
      bikeName: bike?['name'] as String?,
      bikePhotoUrl: bike?['photo_url'] as String?,
      points: rawPoints
          .map((e) => TrackPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      likedByMe: likedByMe,
    );
  }
}

/// Local-first draft waiting to sync to Supabase.
class PendingRide {
  PendingRide({
    required this.localId,
    this.userId,
    required this.title,
    required this.visibility,
    required this.distanceKm,
    required this.movingTimeSecs,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    this.elevationM = 0,
    required this.bikeName,
    this.bikeId,
    required this.points,
    required this.createdAt,
    this.startedAt,
    this.endedAt,
    this.synced = false,
    this.remoteId,
  });

  final String localId;
  final String? userId;
  final String title;
  final RideVisibility visibility;
  final double distanceKm;
  final int movingTimeSecs;
  final double avgSpeedKmh;
  final double maxSpeedKmh;
  final double elevationM;
  final String bikeName;
  final String? bikeId;
  final List<TrackPoint> points;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  bool synced;
  String? remoteId;

  Map<String, dynamic> toJson() => {
        'localId': localId,
        if (userId != null) 'userId': userId,
        'title': title,
        'visibility': visibility.dbValue,
        'distanceKm': distanceKm,
        'movingTimeSecs': movingTimeSecs,
        'avgSpeedKmh': avgSpeedKmh,
        'maxSpeedKmh': maxSpeedKmh,
        'elevationM': elevationM,
        'bikeName': bikeName,
        'bikeId': bikeId,
        'points': points.map((p) => p.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'startedAt': startedAt?.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'synced': synced,
        'remoteId': remoteId,
      };

  factory PendingRide.fromJson(Map<String, dynamic> json) => PendingRide(
        localId: json['localId'] as String,
        userId: json['userId'] as String?,
        title: json['title'] as String? ?? 'Ride',
        visibility: RideVisibility.fromDb(json['visibility'] as String?),
        distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
        movingTimeSecs: json['movingTimeSecs'] as int? ?? 0,
        avgSpeedKmh: (json['avgSpeedKmh'] as num?)?.toDouble() ?? 0,
        maxSpeedKmh: (json['maxSpeedKmh'] as num?)?.toDouble() ?? 0,
        elevationM: (json['elevationM'] as num?)?.toDouble() ?? 0,
        bikeName: json['bikeName'] as String? ?? '',
        bikeId: json['bikeId'] as String?,
        points: (json['points'] as List? ?? [])
            .map(
                (e) => TrackPoint.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        startedAt: json['startedAt'] != null
            ? DateTime.tryParse(json['startedAt'] as String)
            : null,
        endedAt: json['endedAt'] != null
            ? DateTime.tryParse(json['endedAt'] as String)
            : null,
        synced: json['synced'] as bool? ?? false,
        remoteId: json['remoteId'] as String?,
      );

  /// Shown in the rider's own lists/stats until it syncs.
  RideRecord toRecord() => RideRecord(
        id: localId,
        userId: userId ?? '',
        bikeId: bikeId,
        title: title,
        visibility: visibility,
        distanceKm: distanceKm,
        movingTimeSecs: movingTimeSecs,
        avgSpeedKmh: avgSpeedKmh,
        maxSpeedKmh: maxSpeedKmh,
        elevationM: elevationM,
        startedAt: startedAt,
        endedAt: endedAt,
        localId: localId,
        createdAt: createdAt,
      );
}

/// Totals for the Activity page, computed from the rider's own rides.
class RideStats {
  const RideStats({
    required this.rides,
    required this.km,
    required this.elevationM,
    required this.movingSecs,
    required this.weeklyKm,
    required this.monthKm,
  });

  /// Year-to-date totals.
  final int rides;
  final double km;
  final double elevationM;
  final int movingSecs;

  /// Oldest → current week (weeks start Monday, local time).
  final List<double> weeklyKm;

  /// Current calendar month.
  final double monthKm;

  static const empty = RideStats(
    rides: 0,
    km: 0,
    elevationM: 0,
    movingSecs: 0,
    weeklyKm: [0, 0, 0, 0, 0, 0, 0, 0],
    monthKm: 0,
  );

  factory RideStats.compute(
    Iterable<RideRecord> rides, {
    required DateTime now,
    int weeks = 8,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final thisWeek =
        DateTime(today.year, today.month, today.day - (today.weekday - 1));
    final weekStarts = [
      for (var i = weeks - 1; i >= 0; i--)
        DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7 * i),
    ];
    final weekly = List<double>.filled(weeks, 0);
    var count = 0;
    var km = 0.0;
    var elev = 0.0;
    var secs = 0;
    var month = 0.0;

    for (final r in rides) {
      final at = r.rodeAt?.toLocal();
      if (at == null) continue;
      if (at.year == now.year) {
        count += 1;
        km += r.distanceKm;
        elev += r.elevationM;
        secs += r.movingTimeSecs;
        if (at.month == now.month) month += r.distanceKm;
      }
      for (var i = weeks - 1; i >= 0; i--) {
        if (!at.isBefore(weekStarts[i])) {
          if (i < weeks - 1 ||
              at.isBefore(
                  DateTime(thisWeek.year, thisWeek.month, thisWeek.day + 7))) {
            weekly[i] += r.distanceKm;
          }
          break;
        }
      }
    }

    return RideStats(
      rides: count,
      km: km,
      elevationM: elev,
      movingSecs: secs,
      weeklyKm: weekly,
      monthKm: month,
    );
  }
}
