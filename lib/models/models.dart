import 'dart:math' as math;

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

  /// Coordinates are kept to 6 decimals (~11 cm), altitude and accuracy to
  /// 0.1 m, and times to the millisecond: finer than GPS can tell, and it
  /// more than halves the size of a stored track.
  Map<String, dynamic> toJson() => {
        'lat': _round(lat, 1e6),
        'lng': _round(lng, 1e6),
        if (t != null)
          't': t!
              .subtract(Duration(microseconds: t!.microsecond))
              .toIso8601String(),
        if (elev != null && elev!.isFinite) 'elev': _round(elev!, 10),
        if (accuracy != null && accuracy!.isFinite)
          'accuracy': _round(accuracy!, 10),
      };

  static double _round(double v, double scale) => (v * scale).round() / scale;

  factory TrackPoint.fromJson(Map<String, dynamic> json) => TrackPoint(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        t: json['t'] != null ? DateTime.tryParse(json['t'] as String) : null,
        elev: (json['elev'] as num?)?.toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
      );
}

/// A track as it's stored (on the server and in the phone's upload queue):
/// `{"v": 2, "t0": <time of the first fix>, "p": [[lat, lng, dt, elev], …]}`,
/// with dt the seconds since t0 (to 0.1 s) and elev in metres (to 0.1 m);
/// trailing unknowns are left off. About a third of the size of the older
/// list of `{lat, lng, t, elev, accuracy}` objects, which [decodeTrack]
/// still reads.
Map<String, dynamic> encodeTrack(List<TrackPoint> track) {
  DateTime? t0;
  for (final p in track) {
    final t = p.t;
    if (t != null && (t0 == null || t.isBefore(t0))) t0 = t;
  }
  double round(double v, double scale) => (v * scale).round() / scale;
  return {
    'v': 2,
    if (t0 != null) 't0': t0.toUtc().toIso8601String(),
    'p': [
      for (final p in track)
        () {
          final dt = p.t == null || t0 == null
              ? null
              : round(p.t!.difference(t0).inMilliseconds / 1000, 10);
          final elev =
              p.elev != null && p.elev!.isFinite ? round(p.elev!, 10) : null;
          return [
            round(p.lat, 1e6),
            round(p.lng, 1e6),
            if (dt != null || elev != null) dt,
            if (elev != null) elev,
          ];
        }(),
    ],
  };
}

/// Reads a track stored by [encodeTrack], or in the older list-of-objects
/// form.
List<TrackPoint> decodeTrack(Object? stored) {
  if (stored is List) {
    return [
      for (final e in stored)
        if (e is Map) TrackPoint.fromJson(Map<String, dynamic>.from(e)),
    ];
  }
  if (stored is! Map) return const [];
  final t0 = DateTime.tryParse(stored['t0'] as String? ?? '');
  return [
    for (final e in stored['p'] as List? ?? const [])
      if (e is List && e.length >= 2)
        TrackPoint(
          lat: (e[0] as num).toDouble(),
          lng: (e[1] as num).toDouble(),
          t: e.length > 2 && e[2] != null && t0 != null
              ? t0.add(Duration(milliseconds: ((e[2] as num) * 1000).round()))
              : null,
          elev: e.length > 3 ? (e[3] as num?)?.toDouble() : null,
        ),
  ];
}

/// Where a ride's flag stands: the point of [track] furthest from where the
/// ride started, i.e. the place the rider reached (the far end of an out and
/// back, the destination of a one-way ride). Null without a track.
///
/// `supabase/migrations/20261016000000_ride_flags.sql` works out the same
/// point for uploaded rides.
TrackPoint? flagPoint(List<TrackPoint> track) {
  if (track.isEmpty) return null;
  final start = track.first;
  // Equirectangular is plenty to rank points within one ride.
  final lngScale = math.cos(start.lat * math.pi / 180);
  var best = start;
  var bestD = -1.0;
  for (final p in track) {
    final dx = (p.lng - start.lng) * lngScale;
    final dy = p.lat - start.lat;
    final d = dx * dx + dy * dy;
    if (d > bestD) {
      bestD = d;
      best = p;
    }
  }
  return best;
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

  BikeRecord copyWith({double? riddenKm}) => BikeRecord(
        id: id,
        userId: userId,
        name: name,
        make: make,
        model: model,
        year: year,
        odometerKm: odometerKm,
        riddenKm: riddenKm ?? this.riddenKm,
        isPrimary: isPrimary,
        photoUrl: photoUrl,
      );

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
    this.cardImageUrl,
    this.journal,
    this.flagLat,
    this.flagLng,
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

  /// The ride card image (bike photo + stats) the rider posted with it.
  final String? cardImageUrl;

  /// The rider's own words about the ride, for its Ride Journal.
  final String? journal;

  /// Its flag: the furthest point the ride reached (see [flagPoint]). Set by
  /// the server once the track uploads.
  final double? flagLat;
  final double? flagLng;

  /// When the ride happened, for grouping into weeks/months.
  DateTime? get rodeAt => startedAt ?? endedAt ?? createdAt;

  RideRecord copyWith({String? id, int? kudosCount, int? commentsCount}) =>
      RideRecord(
        id: id ?? this.id,
        userId: userId,
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
        kudosCount: kudosCount ?? this.kudosCount,
        commentsCount: commentsCount ?? this.commentsCount,
        localId: localId,
        startPlace: startPlace,
        endPlace: endPlace,
        createdAt: createdAt,
        cardImageUrl: cardImageUrl,
        journal: journal,
        flagLat: flagLat,
        flagLng: flagLng,
      );

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
        cardImageUrl: json['card_image_url'] as String?,
        journal: json['journal'] as String?,
        flagLat: (json['flag_lat'] as num?)?.toDouble(),
        flagLng: (json['flag_lng'] as num?)?.toDouble(),
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
    this.fetchedAt,
    this.previewTrack = false,
  });

  final RideRecord ride;
  final Profile rider;
  final String? bikeName;
  final String? bikePhotoUrl;
  final List<TrackPoint> points;
  final bool likedByMe;

  /// [points] are only the track's preview (as lists load it: up to 200
  /// positions); the ride's page loads the full track.
  final bool previewTrack;

  /// Saved on this device, not uploaded yet.
  final bool pending;

  /// When its counts (and [likedByMe]) were requested from the server, so
  /// newer live updates can be told apart from older ones. Null if unknown.
  final DateTime? fetchedAt;

  FeedItem copyWith({bool? likedByMe, int? kudosCount, int? commentsCount}) =>
      FeedItem(
        ride: kudosCount == null && commentsCount == null
            ? ride
            : ride.copyWith(
                kudosCount: kudosCount, commentsCount: commentsCount),
        rider: rider,
        bikeName: bikeName,
        bikePhotoUrl: bikePhotoUrl,
        points: points,
        likedByMe: likedByMe ?? this.likedByMe,
        pending: pending,
        fetchedAt: fetchedAt,
        previewTrack: previewTrack,
      );

  /// This ride with its full track.
  FeedItem withTrack(List<TrackPoint> track) => FeedItem(
        ride: ride,
        rider: rider,
        bikeName: bikeName,
        bikePhotoUrl: bikePhotoUrl,
        points: track,
        likedByMe: likedByMe,
        pending: pending,
        fetchedAt: fetchedAt,
      );

  /// Where the ride's flag stands: as the server placed it, else worked out
  /// from the track. Null without either.
  ({double lat, double lng})? get flag {
    final r = ride;
    if (r.flagLat != null && r.flagLng != null) {
      return (lat: r.flagLat!, lng: r.flagLng!);
    }
    final p = flagPoint(points);
    return p == null ? null : (lat: p.lat, lng: p.lng);
  }

  /// Parses a `rides` row with embedded `rider`, `bike` and `track`: the
  /// track's `points`, or (in lists) only its `preview`.
  factory FeedItem.fromJson(Map<String, dynamic> json,
      {bool likedByMe = false, DateTime? fetchedAt}) {
    final rider = json['rider'] as Map?;
    final bike = json['bike'] as Map?;
    final track = json['track'];
    // ride_tracks.ride_id is unique, so PostgREST embeds an object; tolerate a list.
    final trackRow =
        track is List ? (track.isEmpty ? null : track.first) : track;
    final trackMap = trackRow as Map?;
    final preview = trackMap != null &&
        !trackMap.containsKey('points') &&
        trackMap.containsKey('preview');
    return FeedItem(
      ride: RideRecord.fromJson(json),
      rider: rider != null
          ? Profile.fromJson(Map<String, dynamic>.from(rider))
          : Profile(id: json['user_id'] as String),
      bikeName: bike?['name'] as String?,
      bikePhotoUrl: bike?['photo_url'] as String?,
      points: decodeTrack(trackMap?[preview ? 'preview' : 'points']),
      likedByMe: likedByMe,
      fetchedAt: fetchedAt,
      previewTrack: preview,
    );
  }
}

/// A photo or video added to a ride before it uploaded. Its file waits on
/// the phone (see `LocalRideStore`) and goes up with the ride, into its
/// journal.
class PendingMedia {
  const PendingMedia({
    required this.id,
    required this.extension,
    this.lat,
    this.lng,
    this.takenAt,
    this.uploaded = false,
  });

  /// Also its file's name, on the phone and once uploaded, so a retried
  /// upload is recognised.
  final String id;

  /// Lower case, without the dot ("jpg").
  final String extension;

  /// Where on the route; null if it isn't placed.
  final double? lat;
  final double? lng;
  final DateTime? takenAt;

  /// In the ride's journal now; its file on the phone is gone.
  final bool uploaded;

  static const _videos = {'mp4', 'm4v', 'mov'};

  bool get isVideo => _videos.contains(extension);
  bool get placed => lat != null && lng != null;
  String get fileName => '$id.$extension';

  PendingMedia markUploaded() => PendingMedia(
        id: id,
        extension: extension,
        lat: lat,
        lng: lng,
        takenAt: takenAt,
        uploaded: true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'extension': extension,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (takenAt != null) 'takenAt': takenAt!.toUtc().toIso8601String(),
        if (uploaded) 'uploaded': true,
      };

  factory PendingMedia.fromJson(Map<String, dynamic> json) => PendingMedia(
        id: json['id'] as String,
        extension: json['extension'] as String? ?? 'jpg',
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        takenAt: DateTime.tryParse(json['takenAt'] as String? ?? ''),
        uploaded: json['uploaded'] as bool? ?? false,
      );
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
    this.hasCard = false,
    this.cardImageUrl,
    this.journal,
    this.media = const [],
    this.startPlace,
    this.endPlace,
  });

  /// What a ride is called until the rider names it, or the place it
  /// reached is known ([placeTitle]).
  static String defaultTitle(double km) => 'Ride · ${km.toStringAsFixed(1)} km';

  /// What a ride is called once the place it reached is known.
  static String placeTitle(String place) => 'Ride to $place';

  /// [title] is one the app gave a ride ([defaultTitle]), not the rider.
  static bool isAutoTitle(String title) =>
      RegExp(r'^Ride · \d+(\.\d)? km$').hasMatch(title);

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

  /// A ride card is posted with this ride. Its image waits on the phone
  /// until it's uploaded, then lives at [cardImageUrl].
  final bool hasCard;
  String? cardImageUrl;

  /// What the rider wrote about it: its journal's words.
  final String? journal;

  /// Photos and videos posted with it, into its journal.
  final List<PendingMedia> media;

  /// Where it set off from, and where it reached (its flag): place names,
  /// looked up once it's finished.
  final String? startPlace;
  final String? endPlace;

  PendingRide copyWith({
    String? userId,
    String? title,
    RideVisibility? visibility,
    bool? hasCard,
    String? bikeId,
    String? bikeName,
    String? journal,
    List<PendingMedia>? media,
    String? startPlace,
    String? endPlace,
    List<TrackPoint>? points,
    bool? synced,
    String? remoteId,
    String? cardImageUrl,
  }) =>
      PendingRide(
        localId: localId,
        userId: userId ?? this.userId,
        title: title ?? this.title,
        visibility: visibility ?? this.visibility,
        distanceKm: distanceKm,
        movingTimeSecs: movingTimeSecs,
        avgSpeedKmh: avgSpeedKmh,
        maxSpeedKmh: maxSpeedKmh,
        elevationM: elevationM,
        bikeName: bikeName ?? this.bikeName,
        bikeId: bikeId ?? this.bikeId,
        points: points ?? this.points,
        createdAt: createdAt,
        startedAt: startedAt,
        endedAt: endedAt,
        synced: synced ?? this.synced,
        remoteId: remoteId ?? this.remoteId,
        hasCard: hasCard ?? this.hasCard,
        cardImageUrl: cardImageUrl ?? this.cardImageUrl,
        // Blank is no words at all.
        journal: journal == null
            ? this.journal
            : (journal.trim().isEmpty ? null : journal),
        media: media ?? this.media,
        startPlace: startPlace ?? this.startPlace,
        endPlace: endPlace ?? this.endPlace,
      );

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
        'points': encodeTrack(points),
        'createdAt': createdAt.toIso8601String(),
        'startedAt': startedAt?.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'synced': synced,
        'remoteId': remoteId,
        'hasCard': hasCard,
        'cardImageUrl': cardImageUrl,
        if (journal != null) 'journal': journal,
        if (media.isNotEmpty) 'media': [for (final m in media) m.toJson()],
        if (startPlace != null) 'startPlace': startPlace,
        if (endPlace != null) 'endPlace': endPlace,
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
        points: decodeTrack(json['points']),
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
        hasCard: json['hasCard'] as bool? ?? false,
        cardImageUrl: json['cardImageUrl'] as String?,
        journal: json['journal'] as String?,
        media: [
          for (final m in json['media'] as List? ?? const [])
            PendingMedia.fromJson(Map<String, dynamic>.from(m as Map)),
        ],
        startPlace: json['startPlace'] as String?,
        endPlace: json['endPlace'] as String?,
      );

  /// Shown in the rider's own lists/stats until it syncs.
  RideRecord toRecord() {
    final flag = flagPoint(points);
    return RideRecord(
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
      cardImageUrl: cardImageUrl,
      journal: journal,
      flagLat: flag?.lat,
      flagLng: flag?.lng,
      startPlace: startPlace,
      endPlace: endPlace,
    );
  }
}

/// A flag a ride planted: where it reached (see [flagPoint]), for a rider's
/// map of flags.
class RideFlag {
  const RideFlag({
    required this.rideId,
    required this.title,
    required this.lat,
    required this.lng,
    this.distanceKm = 0,
    this.rodeAt,
    this.pending = false,
    this.place,
    this.localId,
  });

  final String rideId;

  /// Its ride's id on the phone it was recorded on.
  final String? localId;
  final String title;

  /// The place it reached, once known.
  final String? place;
  final double lat;
  final double lng;
  final double distanceKm;
  final DateTime? rodeAt;

  /// Its ride is still on this phone; [rideId] is its local id.
  final bool pending;

  /// A `rides` row's flag; null if it has none (no track).
  static RideFlag? fromJson(Map<String, dynamic> json) {
    final ride = RideRecord.fromJson(json);
    return fromRecord(ride);
  }

  static RideFlag? fromRecord(RideRecord ride, {bool pending = false}) {
    if (ride.flagLat == null || ride.flagLng == null) return null;
    return RideFlag(
      rideId: ride.id,
      title: ride.title,
      lat: ride.flagLat!,
      lng: ride.flagLng!,
      distanceKm: ride.distanceKm,
      rodeAt: ride.rodeAt,
      pending: pending,
      place: ride.endPlace,
      localId: ride.localId,
    );
  }
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

enum NotificationKind { kudos, follow }

/// Something another rider did that concerns this one: kudos on one of
/// their rides, or a new follower.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.actor,
    this.rideId,
    this.rideTitle,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final NotificationKind kind;

  /// Who gave the kudos or followed.
  final Profile actor;
  final String? rideId;

  /// Null if the ride is gone, or no longer visible.
  final String? rideTitle;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get unread => readAt == null;

  /// A `notifications` row with embedded `actor` (profile) and `ride`.
  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'] as Map?;
    final ride = json['ride'] as Map?;
    return AppNotification(
      id: json['id'] as String,
      kind: NotificationKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => NotificationKind.kudos,
      ),
      actor: actor != null
          ? Profile.fromJson(Map<String, dynamic>.from(actor))
          : Profile(id: json['actor_id'] as String),
      rideId: json['ride_id'] as String?,
      rideTitle: ride?['title'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      readAt: json['read_at'] != null
          ? DateTime.tryParse(json['read_at'] as String)
          : null,
    );
  }
}

enum MediaKind { photo, video }

/// A photo or video in a ride's journal, pinned to where it was taken on
/// the route.
class RideMedia {
  const RideMedia({
    required this.id,
    required this.rideId,
    required this.userId,
    required this.kind,
    required this.url,
    required this.storagePath,
    this.caption,
    this.lat,
    this.lng,
    this.takenAt,
    this.createdAt,
    this.rideTitle,
  });

  final String id;
  final String rideId;
  final String userId;
  final MediaKind kind;
  final String url;

  /// Its file in the `ride-media` bucket.
  final String storagePath;
  final String? caption;

  /// Where on the route; null if it isn't placed.
  final double? lat;
  final double? lng;
  final DateTime? takenAt;
  final DateTime? createdAt;

  /// The ride it's from, when loaded with it (a rider's memories).
  final String? rideTitle;

  bool get isVideo => kind == MediaKind.video;
  bool get placed => lat != null && lng != null;

  RideMedia copyWith({String? caption, double? lat, double? lng}) => RideMedia(
        id: id,
        rideId: rideId,
        userId: userId,
        kind: kind,
        url: url,
        storagePath: storagePath,
        caption: caption ?? this.caption,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        takenAt: takenAt,
        createdAt: createdAt,
        rideTitle: rideTitle,
      );

  factory RideMedia.fromJson(Map<String, dynamic> json) => RideMedia(
        id: json['id'] as String,
        rideId: json['ride_id'] as String,
        userId: json['user_id'] as String,
        kind: json['kind'] == 'video' ? MediaKind.video : MediaKind.photo,
        url: json['url'] as String,
        storagePath: json['storage_path'] as String? ?? '',
        caption: json['caption'] as String?,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        takenAt: json['taken_at'] != null
            ? DateTime.tryParse(json['taken_at'] as String)
            : null,
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)
            : null,
        rideTitle: (json['ride'] as Map?)?['title'] as String?,
      );
}
