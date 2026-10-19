import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../repositories/journal_repository.dart';
import '../services/achievements.dart';
import '../services/media_placement.dart';
import '../services/ride_tracker.dart';
import 'core.dart';
import 'navigation.dart';
import 'rider.dart';
import 'rides.dart';
import 'settings.dart';

/// The bike the rider picked for their next ride, if they picked one.
final pickedBikeIdProvider =
    NotifierProvider<PickedBike, String?>(PickedBike.new);

class PickedBike extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(currentUserIdProvider);
    return null;
  }

  void pick(String bikeId) => state = bikeId;
}

/// The bike the next ride is credited to: the one picked, else the primary.
/// Null until the bikes load (offline, the ride is credited to the primary
/// bike when it syncs).
final selectedBikeProvider = Provider<BikeRecord?>((ref) {
  final bikes = ref.watch(myBikesProvider).value ?? const <BikeRecord>[];
  final picked = ref.watch(pickedBikeIdProvider);
  return bikes.where((b) => b.id == picked).firstOrNull ??
      bikes.where((b) => b.isPrimary).firstOrNull ??
      bikes.firstOrNull;
});

enum RideStatus { idle, riding, paused }

/// Set when the rider should be asked to let Throttle use location in the
/// background ("Always" / "Allow all the time"): right after they allow it
/// only while using the app, and (once per app run) when a ride starts
/// without it. The Record screen asks, then [dismiss]es it.
final backgroundLocationPromptProvider =
    NotifierProvider<BackgroundLocationPrompt, bool>(
        BackgroundLocationPrompt.new);

class BackgroundLocationPrompt extends Notifier<bool> {
  bool _asked = false;

  @override
  bool build() {
    ref.watch(currentUserIdProvider);
    _asked = false;
    return false;
  }

  /// Ask, unless the rider was already asked since the app started.
  void ask() {
    if (_asked) return;
    _asked = true;
    state = true;
  }

  void dismiss() => state = false;
}

/// Asks the system for location "all the time": on Android, its permission
/// screen; on iOS, which only asks once, the app's page in Settings.
Future<void> allowBackgroundLocation() async {
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await Geolocator.requestPermission();
    } else {
      await Geolocator.openAppSettings();
    }
  } catch (e) {
    debugPrint('Couldn\'t ask for background location: $e');
  }
}

/// The ride being recorded, as the Record tab shows it.
@immutable
class Recording {
  const Recording({
    this.status = RideStatus.idle,
    this.secs = 0,
    this.gps = searchingGps,
    this.here,
    this.hereAccuracy,
    this.trail = const [],
    this.km = 0,
    this.speedKmh = 0,
    this.avgKmh = 0,
    this.restored = false,
  });

  static const searchingGps = 'Searching GPS…';

  final RideStatus status;

  /// Wall-clock time while recording (pauses excluded); moving time comes
  /// from the tracker and also excludes stops.
  final int secs;

  /// GPS status line.
  final String gps;

  /// Latest position (any accuracy) for the live "you are here" dot.
  final LatLng? here;
  final double? hereAccuracy;

  /// The recorded track so far.
  final List<LatLng> trail;
  final double km;
  final double speedKmh;
  final double avgKmh;

  /// Brought back, paused, after the app was closed mid-ride.
  final bool restored;
}

/// Records a ride: GPS, the clock and the live stats. FINISH hands the ride
/// over to [finishedRideProvider].
///
/// GPS runs while a ride is in progress (also with the screen off), and
/// while the Record tab is on screen waiting for one; otherwise it's off, to
/// save battery.
///
/// The ride in progress is kept on the phone every few seconds (and when the
/// app goes to the background). If the app is closed or killed mid-ride, it
/// comes back paused the next time, to resume or finish.
final rideRecorderProvider =
    NotifierProvider<RideRecorder, Recording>(RideRecorder.new);

class RideRecorder extends Notifier<Recording> {
  final _tracker = RideTracker();

  /// The recorded track as map points, appended as the tracker accepts fixes.
  final _trail = <LatLng>[];
  List<LatLng> _trailShown = const [];
  RideStatus _status = RideStatus.idle;
  int _secs = 0;
  String _gps = Recording.searchingGps;
  LatLng? _here;
  double? _hereAccuracy;
  DateTime? _startedAt;
  StreamSubscription<Position>? _watch;
  bool _backgroundStream = false;
  Timer? _ticker;
  bool _restored = false;

  /// The ride's id from START, kept when it's finished and resumed, so
  /// photos added after FINISH stay with it.
  String? _localId;

  /// What the rider had already added after FINISH (title, words, photos)
  /// when they resumed: back on the ride when it's finished again.
  Map<String, dynamic>? _details;

  /// Bumped on every rebuild, so a restore for an earlier rider is dropped.
  int _gen = 0;

  /// How often the ride in progress is saved to the phone while riding.
  static const persistEverySecs = 5;

  @override
  Recording build() {
    // A new rider starts over; the last one's ride (and GPS) stop.
    ref.watch(currentUserIdProvider);
    // Leaving the app is when the system may kill it: keep the ride first.
    final lifecycle = AppLifecycleListener(onHide: _persist);
    ref.onDispose(() {
      _ticker?.cancel();
      _watch?.cancel();
      _watch = null;
      lifecycle.dispose();
    });
    _reset();
    _restored = false;
    unawaited(_restoreLive(++_gen));
    _gps = Recording.searchingGps;
    _here = null;
    _hereAccuracy = null;

    ref.listen(currentTabProvider, (_, __) => _updateIdleGps());
    ref.listen(finishedRideProvider.select((ride) => ride != null),
        (_, __) => _updateIdleGps());
    if (_wantsIdleGps) unawaited(_startGps());
    return const Recording();
  }

  /// Between rides, GPS runs only while the Record tab is on screen, and
  /// isn't showing a finished ride.
  bool get _wantsIdleGps =>
      ref.read(currentTabProvider) == AppTab.record &&
      ref.read(finishedRideProvider) == null;

  void _updateIdleGps() {
    if (_status != RideStatus.idle) return;
    _wantsIdleGps ? unawaited(_startGps()) : _stopGps();
  }

  /// START, or RESUME after a pause.
  void ride() {
    if (_status == RideStatus.idle) {
      ref.read(finishedRideProvider.notifier).recordingStarted();
      unawaited(_checkBackgroundLocation());
    }
    _ticker?.cancel();
    _startedAt ??= DateTime.now();
    _localId ??= const Uuid().v4();
    _tracker.start();
    _status = RideStatus.riding;
    _restored = false;
    _emit();
    _persist();
    _listen(background: true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _secs += 1;
      if (_secs % persistEverySecs == 0) _persist();
      _emit();
    });
  }

  void pause() {
    _ticker?.cancel();
    _tracker.pause();
    _status = RideStatus.paused;
    _emit();
    _persist();
  }

  /// Keeps the ride in progress on the phone (see [_restoreLive]).
  void _persist() {
    if (_status == RideStatus.idle || !ref.mounted) return;
    ref.read(localRideStoreProvider).saveLive(_liveJson());
  }

  /// The ride in progress, as kept on the phone, and as a finished ride
  /// keeps it to be resumed (see [resumeFinished]).
  Map<String, dynamic> _liveJson() => {
        'userId': ref.read(currentUserIdProvider),
        'localId': _localId,
        'secs': _secs,
        'startedAt': _startedAt?.toUtc().toIso8601String(),
        'bikeId': ref.read(selectedBikeProvider)?.id ??
            ref.read(pickedBikeIdProvider),
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'tracker': _tracker.toJson(),
        if (_details != null) 'details': _details,
      };

  /// Brings back a ride the app was closed (or killed) in the middle of,
  /// paused: the rider picks up where they were, or finishes it.
  Future<void> _restoreLive(int gen) async {
    final store = ref.read(localRideStoreProvider);
    final uid = ref.read(currentUserIdProvider);
    final saved = await store.loadLive();
    // Another rider's stays on the phone for them.
    if (saved == null || uid == null || saved['userId'] != uid) return;
    // A ride started meanwhile: it's the one being kept now.
    if (!ref.mounted || gen != _gen || _status != RideStatus.idle) return;
    if (!_restoreFrom(saved)) {
      await store.clearLive();
      return;
    }
    _status = RideStatus.paused;
    _restored = true;
    _emit();
  }

  /// Picks the ride up from [saved] (see [_liveJson]); false if it can't.
  bool _restoreFrom(Map<String, dynamic> saved) {
    try {
      _tracker.restore(Map<String, dynamic>.from(saved['tracker'] as Map));
    } catch (e) {
      debugPrint('Couldn\'t restore the ride in progress: $e');
      return false;
    }
    _secs = (saved['secs'] as num?)?.toInt() ?? 0;
    _startedAt = DateTime.tryParse(saved['startedAt'] as String? ?? '');
    _localId = saved['localId'] as String?;
    final details = saved['details'];
    _details = details is Map ? Map<String, dynamic>.from(details) : null;
    final bikeId = saved['bikeId'] as String?;
    if (bikeId != null) ref.read(pickedBikeIdProvider.notifier).pick(bikeId);
    return true;
  }

  /// RESUME after FINISH (it was a mistake): the finished ride carries on
  /// recording from where it stopped. What the rider added to it since
  /// (title, words, photos, bike) comes back when it's finished again.
  void resumeFinished() {
    final finished = ref.read(finishedRideProvider);
    final saved = finished?.resume;
    if (_status != RideStatus.idle ||
        finished == null ||
        saved == null ||
        !finished.canResume) {
      return;
    }
    _gen++; // a restore still on its way is for an older ride
    final bikeId = finished.ride.bikeId;
    if (!_restoreFrom({...saved, if (bikeId != null) 'bikeId': bikeId})) {
      _reset();
      return;
    }
    _details = finished.details;
    ref.read(finishedRideProvider.notifier).handBack();
    _status = RideStatus.paused;
    _restored = false;
    ride();
  }

  /// A ride is starting with location only while the app is in use: offer to
  /// keep recording with the screen off.
  Future<void> _checkBackgroundLocation() async {
    if (!_asksForBackground) return;
    try {
      final permission = await Geolocator.checkPermission();
      if (ref.mounted && permission == LocationPermission.whileInUse) {
        ref.read(backgroundLocationPromptProvider.notifier).ask();
      }
    } catch (_) {
      // Not knowing is no reason to interrupt the ride.
    }
  }

  /// Only phones distinguish "while using" from "always".
  static bool get _asksForBackground =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// FINISH: the ride's numbers are fixed, and it waits in
  /// [finishedRideProvider] for the rider to decide what to do with it.
  void finish() {
    _ticker?.cancel();
    _tracker.pause();
    final ride = _snapshot();
    final elapsed = _secs;
    final resume = _liveJson()..remove('details');
    final details = _details;
    _reset();
    _restored = false;
    // From here it's kept as the finished ride's draft instead.
    unawaited(ref.read(localRideStoreProvider).clearLive());
    _stopGps(); // nothing left to track until the next ride
    ref
        .read(finishedRideProvider.notifier)
        .open(ride, elapsedSecs: elapsed, resume: resume, details: details);
  }

  PendingRide _snapshot() {
    final t = _tracker;
    final km = double.parse(t.distanceKm.toStringAsFixed(3));
    // If GPS never produced a moving segment, fall back to the clock.
    final moving = t.movingSecs > 0 ? t.movingSecs.round() : _secs;
    final now = DateTime.now();
    final bike = ref.read(selectedBikeProvider);
    return PendingRide(
      localId: _localId ?? const Uuid().v4(),
      userId: ref.read(currentUserIdProvider),
      title: PendingRide.defaultTitle(km),
      visibility: ref.read(finishedRideProvider.notifier).visibility,
      distanceKm: km,
      movingTimeSecs: moving,
      avgSpeedKmh: moving > 0 ? km / (moving / 3600) : 0,
      maxSpeedKmh: t.maxSpeedKmh,
      elevationM: t.elevationGainM.roundToDouble(),
      bikeName: bike?.name ?? '',
      bikeId: bike?.id,
      points: List.of(t.points),
      createdAt: now,
      startedAt: _startedAt,
      endedAt: now,
    );
  }

  void _reset() {
    _ticker?.cancel();
    _status = RideStatus.idle;
    _secs = 0;
    _startedAt = null;
    _localId = null;
    _details = null;
    _tracker.reset();
    _trail.clear();
    _trailShown = const [];
  }

  Future<void> _startGps() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(seconds: 5));
      if (!ref.mounted) return;
      if (!enabled) {
        _setGps('GPS unavailable');
        return;
      }

      var permission = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 5));
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 15));
        // They just picked "while using the app": explain why "always"
        // matters before they find out mid-ride.
        if (ref.mounted &&
            _asksForBackground &&
            permission == LocationPermission.whileInUse) {
          ref.read(backgroundLocationPromptProvider.notifier).ask();
        }
      }
      if (!ref.mounted) return;
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _setGps('Allow location to track');
        return;
      }

      // While we waited for permission the rider may have left the tab, a
      // ride may have been restored, or one may have started (and has its
      // own stream).
      if (_status != RideStatus.idle || !_wantsIdleGps) return;
      _listen(background: false);
    } catch (e) {
      debugPrint('GPS start failed: $e');
      if (ref.mounted) _setGps('GPS error');
    }
  }

  void _stopGps() {
    final wasOn =
        _watch != null || _here != null || _gps != Recording.searchingGps;
    _watch?.cancel();
    _watch = null;
    if (!wasOn) return;
    // Don't keep showing a stale "GPS locked" from before.
    _gps = Recording.searchingGps;
    _here = null;
    _hereAccuracy = null;
    _emit();
  }

  /// While a ride is in progress the stream keeps running with the screen
  /// off / phone in a pocket (Android foreground service, iOS background
  /// location). Otherwise it's foreground-only.
  LocationSettings _settings({required bool background}) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 1),
          foregroundNotificationConfig: background
              ? const ForegroundNotificationConfig(
                  notificationTitle: 'Recording ride',
                  notificationText: 'Throttle is tracking your ride',
                  notificationChannelName: 'Ride recording',
                  enableWakeLock: true,
                  setOngoing: true,
                )
              : null,
        );
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 0,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: background,
          showBackgroundLocationIndicator: background,
        );
      default:
        return const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        );
    }
  }

  void _listen({required bool background}) {
    if (_watch != null && _backgroundStream == background) return;
    _watch?.cancel();
    _backgroundStream = background;
    _watch = Geolocator.getPositionStream(
      locationSettings: _settings(background: background),
    ).listen(
      (p) {
        _gps = 'GPS locked · ±${p.accuracy.round()} m';
        _tracker.addFix(GpsFix(
          lat: p.latitude,
          lng: p.longitude,
          time: p.timestamp,
          accuracyM: p.accuracy,
          speedMps: p.speed,
          speedAccuracyMps: p.speedAccuracy,
          altitudeM: p.altitude,
          altitudeAccuracyM: p.altitudeAccuracy,
        ));
        _here = LatLng(p.latitude, p.longitude);
        _hereAccuracy = p.accuracy;
        _emit();
      },
      onError: (Object error) {
        debugPrint('Position stream error: $error');
        _setGps('Location error');
      },
    );
  }

  void _setGps(String gps) {
    _gps = gps;
    _emit();
  }

  void _emit() {
    final points = _tracker.points;
    for (var i = _trail.length; i < points.length; i++) {
      _trail.add(LatLng(points[i].lat, points[i].lng));
    }
    if (_trailShown.length != _trail.length) {
      _trailShown = List.unmodifiable(_trail);
    }
    state = Recording(
      status: _status,
      secs: _secs,
      gps: _gps,
      here: _here,
      hereAccuracy: _hereAccuracy,
      trail: _trailShown,
      km: _tracker.distanceKm,
      speedKmh: _tracker.currentSpeedKmh,
      avgKmh: _tracker.avgSpeedKmh,
      restored: _restored,
    );
  }
}

/// A finished ride: saved as soon as it's finished, then shown off and
/// edited until the rider is done with it.
@immutable
class FinishedRide {
  const FinishedRide({
    required this.ride,
    required this.visibility,
    required this.attachCard,
    this.bikePhotoUrl,
    this.elapsedSecs = 0,
    this.restored = false,
    this.saving = false,
    this.saved,
    this.saveError,
    this.resume,
    this.achievements,
  });

  /// Its numbers are fixed at FINISH: the summary, the ride card and the
  /// saved ride all use these, so they always match. What the rider adds
  /// after (title, words, bike, photos) and its place names are kept on it
  /// too.
  final PendingRide ride;

  /// Who can see it.
  final RideVisibility visibility;

  /// Whether its ride card is posted with it.
  final bool attachCard;

  /// The photo of the bike it's credited to, if it has one.
  final String? bikePhotoUrl;

  /// How long it was recorded for (unknown, 0, for a restored ride).
  final int elapsedSecs;

  /// It was left unsaved the last time the app was open.
  final bool restored;

  /// Being saved (on the phone, then uploaded).
  final bool saving;

  /// Set once it's saved: on the phone, and uploaded if [PendingRide.synced].
  final PendingRide? saved;
  final String? saveError;

  /// The recording as it was at FINISH, to carry on with it (RESUME).
  final Map<String, dynamic>? resume;

  /// What it earned, once worked out.
  final RideAchievements? achievements;

  /// Finished by mistake? It can carry on recording (once it's done
  /// saving, so the saved ride is the one that carries on).
  bool get canResume => resume != null && !saving;

  /// Saved (and celebrated) as soon as it's finished. An accidental
  /// START/FINISH isn't: it waits for SAVE RIDE.
  bool get worthSaving =>
      ride.distanceKm >= FinishedRideNotifier.minKeepKm ||
      ride.media.isNotEmpty;

  /// What it's called unless the rider names it: "Ride to Nagarkot" once
  /// the place it reached is known.
  String get defaultTitle => ride.endPlace != null
      ? PendingRide.placeTitle(ride.endPlace!)
      : PendingRide.defaultTitle(ride.distanceKm);

  /// The title the rider gave it; empty while it has a default one.
  String get customTitle => ride.title == defaultTitle ||
          ride.title == PendingRide.defaultTitle(ride.distanceKm)
      ? ''
      : ride.title;

  /// The ride as the ride card and share screen show it.
  FeedItem get item => FeedItem(
        ride: ride.toRecord(),
        rider: Profile(id: ride.userId ?? ''),
        bikeName: ride.bikeName.isEmpty ? null : ride.bikeName,
        bikePhotoUrl: bikePhotoUrl,
        points: ride.points,
        pending: saved?.synced != true,
      );

  /// What the rider added after FINISH, to keep while it's resumed.
  Map<String, dynamic> get details => {
        if (customTitle.isNotEmpty) 'title': customTitle,
        if (ride.journal != null) 'journal': ride.journal,
        if (ride.media.isNotEmpty)
          'media': [for (final m in ride.media) m.toJson()],
        'attachCard': attachCard,
      };

  static const _keep = Object();

  FinishedRide copyWith({
    PendingRide? ride,
    RideVisibility? visibility,
    bool? attachCard,
    Object? bikePhotoUrl = _keep,
    bool? saving,
    PendingRide? saved,
    Object? saveError = _keep,
    RideAchievements? achievements,
  }) =>
      FinishedRide(
        ride: ride ?? this.ride,
        visibility: visibility ?? this.visibility,
        attachCard: attachCard ?? this.attachCard,
        bikePhotoUrl: identical(bikePhotoUrl, _keep)
            ? this.bikePhotoUrl
            : bikePhotoUrl as String?,
        elapsedSecs: elapsedSecs,
        restored: restored,
        saving: saving ?? this.saving,
        saved: saved ?? this.saved,
        saveError:
            identical(saveError, _keep) ? this.saveError : saveError as String?,
        resume: resume,
        achievements: achievements ?? this.achievements,
      );
}

/// Photos and videos added to a finished ride: how many went in, how many
/// don't say where they were taken, and how many couldn't be added.
typedef AddedMedia = ({int added, int unplaced, int skipped});

/// The ride just finished, from FINISH (or a ride left unsaved when the app
/// last closed) until the rider is done with it. It's saved straight away;
/// what the rider changes after goes to the saved ride. Null while there's
/// none.
final finishedRideProvider =
    NotifierProvider<FinishedRideNotifier, FinishedRide?>(
        FinishedRideNotifier.new);

class FinishedRideNotifier extends Notifier<FinishedRide?> {
  /// Shorter rides (an accidental START/FINISH) aren't kept as a draft and
  /// can be discarded without asking.
  static const minKeepKm = 0.05;

  /// Who can see the next ride: what the rider picked for the last one.
  RideVisibility visibility = RideVisibility.public;

  /// Bumped whenever the ride in question changes (one opens or closes, or a
  /// new one starts), so work for an earlier one (a save, a restore) doesn't
  /// land on the next.
  int _gen = 0;

  /// Typing goes to the saved ride once it pauses.
  Timer? _pushTimer;

  /// The save under way, so changes wait for it.
  Future<void>? _saving;

  @override
  FinishedRide? build() {
    ref.watch(currentUserIdProvider);
    ref.onDispose(() => _pushTimer?.cancel());
    visibility = RideVisibility.public;
    unawaited(_restoreDraft(++_gen));
    return null;
  }

  /// FINISH. The ride is saved straight away (and kept on the phone till
  /// then). [resume] is the recording, to carry on with it; [details] what
  /// the rider added before resuming it last time.
  void open(PendingRide ride,
      {required int elapsedSecs,
      Map<String, dynamic>? resume,
      Map<String, dynamic>? details}) {
    final gen = ++_gen;
    var finished = _finished(ride, ref.read(myBikesProvider).value,
        elapsedSecs: elapsedSecs, resume: resume);
    if (details != null) finished = _withDetails(finished, details);
    state = finished;
    _keepDraft(finished);
    _start(gen);
  }

  /// Saving, and what's worked out about the ride meanwhile.
  void _start(int gen) {
    if (!(state?.worthSaving ?? false)) return;
    _saving = _save(gen);
    unawaited(_achievements(gen));
    unawaited(_namePlaces(gen));
  }

  FinishedRide _withDetails(
      FinishedRide finished, Map<String, dynamic> details) {
    final title = details['title'] as String?;
    return finished.copyWith(
      ride: finished.ride.copyWith(
        title: title,
        journal: details['journal'] as String?,
        media: [
          for (final m in details['media'] as List? ?? const [])
            PendingMedia.fromJson(Map<String, dynamic>.from(m as Map)),
        ],
      ),
      attachCard: details['attachCard'] as bool?,
    );
  }

  /// Keeps [finished] on the phone as the draft until it's saved, so
  /// closing the app first doesn't lose it.
  void _keepDraft(FinishedRide finished) {
    final ride = finished.ride;
    if (finished.saved != null ||
        (ride.distanceKm < minKeepKm && ride.media.isEmpty)) {
      return;
    }
    ref
        .read(localRideStoreProvider)
        .saveDraft(ride.copyWith(visibility: finished.visibility),
            resume: finished.resume)
        .catchError((Object e) =>
            debugPrint('Couldn\'t keep the ride on this phone: $e'));
  }

  /// Brings back a ride that was left unsaved when the app closed, and
  /// saves it.
  Future<void> _restoreDraft(int gen) async {
    try {
      final uid = ref.read(currentUserIdProvider);
      final store = ref.read(localRideStoreProvider);
      final draft = await store.loadDraftWithResume();
      if (draft == null || draft.ride.userId != uid) return;
      // The app closed while saving it: it's already in the upload queue.
      if ((await store.find(draft.ride.localId)) != null) {
        await store.clearDraft();
        return;
      }
      // Wait (briefly) for the bike, to offer its photo for the ride card.
      List<BikeRecord>? bikes;
      try {
        bikes = await ref
            .read(myBikesProvider.future)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // Restored without the photo.
      }
      if (!ref.mounted || gen != _gen) return;
      visibility = draft.ride.visibility;
      state =
          _finished(draft.ride, bikes, restored: true, resume: draft.resume);
      _start(gen);
    } catch (e) {
      debugPrint('Couldn\'t restore the unsaved ride: $e');
    }
  }

  /// The ride card starts as the bike's photo, attached, when there is one.
  FinishedRide _finished(PendingRide ride, List<BikeRecord>? bikes,
      {int elapsedSecs = 0,
      bool restored = false,
      Map<String, dynamic>? resume}) {
    final photo =
        bikes?.where((b) => b.id == ride.bikeId).firstOrNull?.photoUrl;
    return FinishedRide(
      ride: ride,
      visibility: visibility,
      attachCard: photo != null,
      bikePhotoUrl: photo,
      elapsedSecs: elapsedSecs,
      restored: restored,
      resume: resume,
    );
  }

  /// A new ride started: an unsaved one still being restored isn't shown
  /// over it.
  void recordingStarted() => _gen++;

  /// Saves the ride: on the phone first, then uploaded (or synced later if
  /// offline). Its ride card follows separately ([setCard]).
  Future<void> _save(int gen) async {
    final ride = state;
    if (ride == null || ride.saving || ride.saved != null) return;
    state = ride.copyWith(saving: true, saveError: null);
    try {
      final saved = await ref
          .read(rideRepositoryProvider)
          .saveRide(ride.ride.copyWith(visibility: ride.visibility));
      if (!ref.mounted || gen != _gen) return;
      state = state?.copyWith(saving: false, saved: saved);
      // Anything changed while it was saving goes to the saved ride (not
      // awaited: the push waits for this save to be done).
      final now = state!;
      if (!identical(now.ride, ride.ride) ||
          now.visibility != ride.visibility) {
        unawaited(_push(gen));
      }
    } catch (e) {
      debugPrint('Ride save failed: $e');
      if (ref.mounted && gen == _gen) {
        state = state?.copyWith(
            saving: false, saveError: 'Couldn\'t save this ride. Try again.');
      }
    }
  }

  /// SAVE RIDE (a short ride isn't saved by itself), or tries again after
  /// saving failed.
  Future<void> save() {
    final ride = state;
    if (ride == null || ride.saving || ride.saved != null) {
      return Future.value();
    }
    final gen = _gen;
    if (ride.achievements == null) unawaited(_achievements(gen));
    return _saving = _save(gen);
  }

  /// Which flag it is and what it earned, against every other ride the
  /// rider has saved (uploaded, or still on the phone). Earns nothing if
  /// those can't be loaded (offline).
  Future<void> _achievements(int gen) async {
    final ride = state?.ride;
    if (ride == null) return;
    RideAchievements result;
    try {
      // Already loaded (Activity, Profile), else straight from the server:
      // the provider reloads as this ride saves.
      final history = ref.read(myRideHistoryProvider).value ??
          await ref
              .read(rideRepositoryProvider)
              .myRideHistory()
              .timeout(const Duration(seconds: 8));
      final pending = await ref.read(rideRepositoryProvider).myPendingRides();
      final uploaded =
          history.map((r) => r.localId).whereType<String>().toSet();
      result = RideAchievements.compute(units: ref.read(unitsProvider), ride, [
        for (final r in history)
          if (r.localId != ride.localId) r,
        for (final p in pending)
          if (p.localId != ride.localId && !uploaded.contains(p.localId))
            p.toRecord(),
      ]);
    } catch (_) {
      result = RideAchievements.compute(ride, null);
    }
    if (ref.mounted && gen == _gen) {
      state = state?.copyWith(achievements: result);
    }
  }

  /// Where it set off from and where it reached, by name.
  Future<void> _namePlaces(int gen) async {
    final ride = state?.ride;
    final points = ride?.points ?? const <TrackPoint>[];
    final flag = flagPoint(points);
    if (ride == null || flag == null) return;
    final places = ref.read(placeNamesProvider);
    final start = await places.nameOf(points.first.lat, points.first.lng);
    final end = await places.nameOf(flag.lat, flag.lng);
    if (!ref.mounted || gen != _gen || (start == null && end == null)) return;
    // Named after where it went, unless the rider named it.
    _edit((r) => r.copyWith(
        ride: r.ride.copyWith(
            startPlace: start,
            endPlace: end,
            title: end != null && r.customTitle.isEmpty
                ? PendingRide.placeTitle(end)
                : null)));
  }

  /// A change to the ride: kept on the phone (as the draft, before it's
  /// saved) and sent to the saved ride ([soon]: once typing pauses).
  void _edit(FinishedRide Function(FinishedRide ride) change,
      {bool soon = false}) {
    final ride = state;
    if (ride == null) return;
    state = change(ride);
    if (state!.saved == null) {
      _keepDraft(state!);
      return;
    }
    _pushTimer?.cancel();
    if (soon) {
      final gen = _gen;
      _pushTimer = Timer(const Duration(milliseconds: 800), () => _push(gen));
    } else {
      unawaited(_push(_gen));
    }
  }

  /// Sends what's changed to the saved ride (see
  /// [RideRepository.updateSaved]).
  Future<void> _push(int gen) async {
    _pushTimer?.cancel();
    await _saving;
    final ride = state;
    if (!ref.mounted || gen != _gen || ride?.saved == null) return;
    try {
      final updated = await ref
          .read(rideRepositoryProvider)
          .updateSaved(ride!.ride.copyWith(visibility: ride.visibility));
      if (ref.mounted && gen == _gen) {
        state = state?.copyWith(saved: updated);
      }
    } catch (e) {
      debugPrint('Couldn\'t change the saved ride: $e');
    }
  }

  void setVisibility(RideVisibility value) {
    visibility = value; // the next ride starts with it too
    _edit((r) => r.copyWith(visibility: value));
  }

  /// What it's called; blank gives it back its default title.
  void setTitle(String title) => _edit(
      (r) => r.copyWith(
          ride: r.ride.copyWith(
              title: title.trim().isEmpty ? r.defaultTitle : title.trim())),
      soon: true);

  /// What the rider wants to say about it.
  void setJournal(String text) =>
      _edit((r) => r.copyWith(ride: r.ride.copyWith(journal: text)),
          soon: true);

  /// Credits it to [bike] instead (and the next ride starts with it).
  void setBike(BikeRecord bike) {
    _edit((r) => r.copyWith(
          ride: r.ride.copyWith(bikeId: bike.id, bikeName: bike.name),
          bikePhotoUrl: bike.photoUrl,
        ));
    ref.read(pickedBikeIdProvider.notifier).pick(bike.id);
  }

  /// Whether its ride card is posted with it. Attached, the card itself
  /// follows ([setCard]); taken off, it goes now.
  void setAttachCard(bool attach) {
    final ride = state;
    if (ride == null) return;
    if (attach) {
      state = ride.copyWith(attachCard: true);
    } else {
      unawaited(setCard(null));
    }
  }

  /// Posts [jpeg] as its ride card, or takes the card off (null).
  Future<void> setCard(Uint8List? jpeg) async {
    final gen = _gen;
    final ride = state;
    if (ride == null) return;
    state = ride.copyWith(attachCard: jpeg != null);
    await _saving;
    final saved = state?.saved;
    if (!ref.mounted || gen != _gen || saved == null) return;
    try {
      final updated =
          await ref.read(rideRepositoryProvider).setCard(saved, jpeg);
      if (ref.mounted && gen == _gen) {
        state = state?.copyWith(saved: updated);
      }
    } catch (e) {
      debugPrint('Couldn\'t change the ride card: $e');
    }
  }

  /// Adds photos and videos to the ride: kept on the phone until it
  /// uploads, then into its journal, each where it was taken on the route
  /// when it says.
  Future<AddedMedia> addMedia(List<XFile> files) async {
    var added = 0, unplaced = 0, skipped = 0;
    final localId = state?.ride.localId;
    for (final file in files) {
      final ride = state;
      if (ride == null || ride.ride.localId != localId) break;
      try {
        final ext = JournalRepository.extensionFor(file.name, file.mimeType);
        if (ext == null) {
          skipped++;
          continue;
        }
        final bytes = await file.readAsBytes();
        if (bytes.length > JournalRepository.maxBytes) {
          skipped++;
          continue;
        }
        final meta = JournalRepository.isVideo(ext)
            ? const PhotoMeta()
            : readPhotoMeta(bytes);
        final track = ride.ride.points;
        final place = placeOnRoute(track,
            lat: meta.lat, lng: meta.lng, takenAt: meta.takenAt);
        final at = place == null ? null : track[place.index];
        final media = PendingMedia(
          id: const Uuid().v4(),
          extension: ext,
          lat: at?.lat,
          lng: at?.lng,
          takenAt: meta.takenAt,
        );
        await ref
            .read(localRideStoreProvider)
            .saveMedia(localId!, media, bytes);
        if (!ref.mounted || state?.ride.localId != localId) break;
        _edit((r) =>
            r.copyWith(ride: r.ride.copyWith(media: [...r.ride.media, media])));
        added++;
        if (at == null) unplaced++;
      } catch (e) {
        debugPrint('Couldn\'t add a photo to the ride: $e');
        skipped++;
      }
    }
    return (added: added, unplaced: unplaced, skipped: skipped);
  }

  Future<void> removeMedia(PendingMedia media) async {
    final ride = state;
    if (ride == null) return;
    state = ride.copyWith(
        ride: ride.ride.copyWith(media: [
      for (final m in ride.ride.media)
        if (m.id != media.id) m
    ]));
    if (state!.saved == null) {
      _keepDraft(state!);
      unawaited(ref
          .read(localRideStoreProvider)
          .deleteMedia(ride.ride.localId, media));
      return;
    }
    try {
      await ref.read(rideRepositoryProvider).removeMedia(state!.saved!, media);
    } catch (e) {
      debugPrint('Couldn\'t remove a photo: $e');
    }
  }

  /// RESUME: the ride goes back to [rideRecorderProvider] (see
  /// [RideRecorder.resumeFinished]), which keeps it as the ride in progress
  /// again. Once saved, it stays saved, and is brought up to date when it's
  /// finished again.
  void handBack() {
    _gen++;
    _pushTimer?.cancel();
    ref.read(localRideStoreProvider).clearDraft().catchError(
        (Object e) => debugPrint('Couldn\'t clear the unsaved ride: $e'));
    state = null;
  }

  /// DONE: on to the next ride.
  void close() {
    final ride = state;
    // Typing not sent yet goes now.
    if (_pushTimer?.isActive ?? false) {
      _pushTimer!.cancel();
      if (ride?.saved != null) {
        unawaited(ref
            .read(rideRepositoryProvider)
            .updateSaved(ride!.ride.copyWith(visibility: ride.visibility))
            .catchError((Object e) {
          debugPrint('Couldn\'t change the saved ride: $e');
          return ride.ride;
        }));
      }
    }
    _gen++;
    state = null;
  }

  /// DISCARD: the ride goes, saved or not, with the photos added to it.
  /// Throws if an uploaded ride can't be deleted (offline).
  Future<void> discard() async {
    final ride = state;
    if (ride == null) return;
    await _saving;
    final saved = state?.saved;
    final store = ref.read(localRideStoreProvider);
    if (saved != null) {
      await ref.read(rideRepositoryProvider).deleteSavedRide(saved);
    } else {
      await store.clearDraft().catchError(
          (Object e) => debugPrint('Couldn\'t clear the unsaved ride: $e'));
      await store.deleteAllMedia(ride.ride.localId);
    }
    if (ref.mounted) close();
  }
}
