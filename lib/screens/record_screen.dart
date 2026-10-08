import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../repositories/bike_repository.dart';
import '../repositories/ride_repository.dart';
import 'share_ride_screen.dart';
import '../services/ride_tracker.dart';
import '../theme.dart';
import '../widgets/tracked_route_map.dart';
import '../widgets/ui.dart';

enum RideStatus { idle, riding, paused, done }

const privacyOpts = ['Public', 'Followers', 'Private'];

String fmt(int s) {
  final h = (s ~/ 3600).toString().padLeft(2, '0');
  final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
  final sec = (s % 60).toString().padLeft(2, '0');
  return '$h:$m:$sec';
}

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  RideStatus status = RideStatus.idle;

  /// Wall-clock time while recording (pauses excluded); moving time comes
  /// from the tracker and also excludes stops.
  int secs = 0;
  String gps = 'Searching GPS…';
  String privacy = 'Followers';
  final _tracker = RideTracker();
  DateTime? _startedAt;
  StreamSubscription<Position>? watch;
  bool _backgroundStream = false;
  Timer? ticker;

  /// Rides shorter than this (accidental START/FINISH) aren't auto-saved.
  static const _minAutoSaveKm = 0.05;

  bool _saving = false;
  PendingRide? _saved;
  String? _saveError;

  /// The finished ride's numbers, fixed at FINISH. Sharing uses this right
  /// away; saving uses the same values so the image and the saved ride match.
  RideRecord? _finished;

  /// Bumped on reset, so a save that completes after "Done" doesn't attach
  /// itself to the next ride.
  int _rideGen = 0;
  List<BikeRecord> _bikes = [];
  String? _bikeId;

  BikeRecord? get _bike => _bikes.where((b) => b.id == _bikeId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _loadBikes();
    _startGps();
  }

  Future<void> _loadBikes() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final bikes = await BikeRepository().listForUser(uid);
      if (!mounted) return;
      setState(() {
        _bikes = bikes;
        if (_bike == null && bikes.isNotEmpty) {
          _bikeId = bikes
              .firstWhere((b) => b.isPrimary, orElse: () => bikes.first)
              .id;
        }
      });
    } catch (_) {
      // Offline: the ride is credited to the primary bike when it syncs.
    }
  }

  /// Called automatically on FINISH: the ride goes to the device first and
  /// then to the rider's account (or syncs later if offline).
  Future<void> _saveRide() async {
    final r = _finished;
    if (r == null || _saving || _saved != null) return;
    final gen = _rideGen;
    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final saved = await RideRepository().shareRide(
        title: r.title,
        visibility: r.visibility,
        distanceKm: r.distanceKm,
        movingTimeSecs: r.movingTimeSecs,
        avgSpeedKmh: r.avgSpeedKmh,
        maxSpeedKmh: r.maxSpeedKmh,
        elevationM: r.elevationM,
        bikeId: _bike?.id,
        bikeName: _bike?.name ?? '',
        points: List.of(_tracker.points),
        startedAt: r.startedAt,
        endedAt: r.endedAt,
      );
      _loadBikes(); // refresh ridden km
      if (!mounted || gen != _rideGen) return;
      setState(() => _saved = saved);
    } catch (e) {
      debugPrint('Ride save failed: $e');
      if (mounted && gen == _rideGen) {
        setState(
            () => _saveError = 'Couldn\'t save this ride. Tap Retry save.');
      }
    } finally {
      if (mounted && gen == _rideGen) setState(() => _saving = false);
    }
  }

  /// Freezes the ride's stats the moment it ends.
  RideRecord _snapshot() {
    final t = _tracker;
    final km = double.parse(t.distanceKm.toStringAsFixed(3));
    // If GPS never produced a moving segment, fall back to the clock.
    final moving = t.movingSecs > 0 ? t.movingSecs.round() : secs;
    String uid = '';
    try {
      uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    } catch (_) {}
    return RideRecord(
      id: 'finished',
      userId: uid,
      bikeId: _bike?.id,
      title: 'Ride · ${km.toStringAsFixed(1)} km',
      visibility: RideVisibility.fromLabel(privacy),
      distanceKm: km,
      movingTimeSecs: moving,
      avgSpeedKmh: moving > 0 ? km / (moving / 3600) : 0,
      maxSpeedKmh: t.maxSpeedKmh,
      elevationM: t.elevationGainM.roundToDouble(),
      startedAt: _startedAt,
      endedAt: DateTime.now(),
    );
  }

  Future<void> _deleteRide() async {
    final saved = _saved;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this ride?'),
        content: const Text('It will be removed from your profile and stats.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (saved == null) {
      _reset();
      return;
    }
    try {
      await RideRepository().deleteSavedRide(saved);
      _loadBikes();
      if (mounted) _reset();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Couldn\'t delete — try again when online ($e)')),
      );
    }
  }

  /// Available as soon as the ride ends; doesn't wait for the save.
  void _openShare() {
    final r = _finished;
    if (r == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ShareRideScreen(
        item: FeedItem(
          ride: r,
          rider: Profile(id: r.userId),
          bikeName: _bike?.name,
          bikePhotoUrl: _bike?.photoUrl,
          points: List.of(_tracker.points),
          pending: _saved?.synced != true,
        ),
      ),
    ));
  }

  Future<void> _startGps() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(seconds: 5));
      if (!enabled) {
        if (mounted) setState(() => gps = 'GPS unavailable');
        return;
      }

      var permission = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 5));
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 15));
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => gps = 'Allow location to track');
        return;
      }

      _listen(background: false);
    } catch (e) {
      debugPrint('GPS start failed: $e');
      if (mounted) setState(() => gps = 'GPS error');
    }
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
    if (watch != null && _backgroundStream == background) return;
    watch?.cancel();
    _backgroundStream = background;
    watch = Geolocator.getPositionStream(
      locationSettings: _settings(background: background),
    ).listen(
      (p) {
        if (!mounted) return;
        setState(() {
          gps = 'GPS locked · ±${p.accuracy.round()} m';
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
        });
      },
      onError: (Object error) {
        debugPrint('Position stream error: $error');
        if (mounted) setState(() => gps = 'Location error');
      },
    );
  }

  void _setStatus(RideStatus next) {
    ticker?.cancel();
    setState(() {
      if (next == RideStatus.riding) {
        _startedAt ??= DateTime.now();
        _tracker.start();
      } else {
        _tracker.pause();
      }
      status = next;
    });
    if (next == RideStatus.riding) {
      _listen(background: true);
      ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => secs += 1);
      });
    } else if (next == RideStatus.done) {
      _listen(background: false);
      _finished = _snapshot();
      if (km >= _minAutoSaveKm) _saveRide();
    }
  }

  void _reset() {
    ticker?.cancel();
    _listen(background: false);
    setState(() {
      status = RideStatus.idle;
      secs = 0;
      _startedAt = null;
      _finished = null;
      _rideGen++;
      _saving = false;
      _saved = null;
      _saveError = null;
      _tracker.reset();
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    watch?.cancel();
    super.dispose();
  }

  Widget _saveStatus() {
    IconData icon = Icons.info_outline;
    var color = AppColors.mutedForeground;
    var text =
        'Too short to save automatically (under ${(_minAutoSaveKm * 1000).round()} m)';
    if (_saving) {
      text = 'Saving to your profile…';
    } else if (_saveError != null) {
      icon = Icons.error_outline;
      color = Colors.redAccent;
      text = _saveError!;
    } else if (_saved?.synced == true) {
      icon = Icons.check_circle;
      color = AppColors.primary;
      text = 'Saved to your profile';
    } else if (_saved != null) {
      icon = Icons.cloud_off_outlined;
      color = AppColors.primary;
      text = 'Saved on this phone — adds to your profile when you\'re online';
    }
    return Row(
      children: [
        _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
            child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: color),
        )),
      ],
    );
  }

  double get km => _tracker.distanceKm;
  int get speed => _tracker.currentSpeedKmh.round();
  int get top => _tracker.maxSpeedKmh.round();
  int get movingSecs => _tracker.movingSecs.round();
  int get avg => _tracker.avgSpeedKmh.round();

  @override
  Widget build(BuildContext context) {
    if (status == RideStatus.done) {
      // Actions are pinned below the scrolling summary so SHARE RIDE is on
      // screen the moment the ride ends, on any phone size.
      return Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              children: [
                RiseIn(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LabelMono('Ride complete', color: AppColors.primary),
                      const SizedBox(height: 4),
                      Text('Nice ride.', style: displayStyle(size: 34)),
                      const SizedBox(height: 16),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TrackedRouteMap.track(_tracker.points, height: 220),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Wrap(
                                runSpacing: 16,
                                children: [
                                  SizedBox(
                                    width:
                                        MediaQuery.sizeOf(context).width / 2 -
                                            32,
                                    child: StatBlock(
                                        value: km.toStringAsFixed(2),
                                        label: 'km',
                                        valueSize: 30),
                                  ),
                                  SizedBox(
                                    width:
                                        MediaQuery.sizeOf(context).width / 2 -
                                            32,
                                    child: StatBlock(
                                        value: fmt(movingSecs),
                                        label: 'moving time',
                                        valueSize: 30),
                                  ),
                                  SizedBox(
                                    width:
                                        MediaQuery.sizeOf(context).width / 2 -
                                            32,
                                    child: StatBlock(
                                        value: '$avg',
                                        label: 'avg km/h',
                                        valueSize: 30),
                                  ),
                                  SizedBox(
                                    width:
                                        MediaQuery.sizeOf(context).width / 2 -
                                            32,
                                    child: StatBlock(
                                        value: '$top',
                                        label: 'top km/h',
                                        valueSize: 30),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: const BoxDecoration(
                                border: Border(
                                    top: BorderSide(color: AppColors.border)),
                              ),
                              child: Text(
                                [
                                  if (_bike != null) _bike!.name,
                                  privacy,
                                  '${_tracker.elevationGainM.round()} m climbed',
                                  'elapsed ${fmt(secs)}',
                                ].join(' · '),
                                style: monoStyle(size: 11, tracking: 0),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _saveStatus(),
                const SizedBox(height: 12),
                SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _openShare,
                    icon: const Icon(Icons.ios_share),
                    label: Text(
                      'SHARE RIDE',
                      style: displayStyle(
                          size: 20, color: AppColors.primaryForeground),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Saved or saving: Done + Delete. Not saved (too short or
                // failed): Save + Discard.
                if (_saved != null || _saving)
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _reset,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.foreground,
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Done',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  )
                else
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _saveRide,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.foreground,
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                          _saveError != null ? 'Retry save' : 'Save anyway',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                Center(
                  child: TextButton(
                    onPressed: _saving
                        ? null
                        : (_saved != null ? _deleteRide : _reset),
                    child: Text(
                      _saved != null || _saving ? 'Delete ride' : 'Discard',
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.mutedForeground),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final label = status == RideStatus.riding
        ? 'Recording'
        : status == RideStatus.paused
            ? 'Paused'
            : 'Record';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label.toUpperCase(), style: labelMono(size: 11)),
            Row(
              children: [
                const BlinkDot(),
                const SizedBox(width: 8),
                Text(gps, style: monoStyle(size: 11, tracking: 0)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        RiseIn(
          child: AppCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const LabelMono('Speed'),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '$speed', style: displayStyle(size: 88)),
                      TextSpan(
                          text: ' km/h',
                          style: displayStyle(
                              size: 18, color: AppColors.mutedForeground)),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                        child: _Cell(
                            v: km.toStringAsFixed(2), u: 'km', l: 'Distance')),
                    const SizedBox(width: 12),
                    Expanded(child: _Cell(v: fmt(secs), u: '', l: 'Time')),
                    const SizedBox(width: 12),
                    Expanded(child: _Cell(v: '$avg', u: 'km/h', l: 'Avg')),
                  ],
                ),
                const SizedBox(height: 20),
                if (status == RideStatus.idle)
                  SheenButton(
                    onTap: () => _setStatus(RideStatus.riding),
                    child: Container(
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text('START',
                          style: displayStyle(
                              size: 24, color: AppColors.primaryForeground)),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 64,
                          child: FilledButton(
                            onPressed: () => _setStatus(
                              status == RideStatus.riding
                                  ? RideStatus.paused
                                  : RideStatus.riding,
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.secondary,
                              foregroundColor: AppColors.foreground,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Text(
                              status == RideStatus.riding ? 'PAUSE' : 'RESUME',
                              style: displayStyle(size: 20),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 64,
                          child: FilledButton(
                            onPressed: () => _setStatus(RideStatus.done),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.foreground,
                              foregroundColor: AppColors.background,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Text('FINISH',
                                style: displayStyle(
                                    size: 20, color: AppColors.background)),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (status == RideStatus.idle) ...[
          const SizedBox(height: 16),
          if (_bikes.isNotEmpty)
            _Picker(
              label: 'Motorcycle',
              options: [for (final b in _bikes) b.name],
              value: _bike?.name ?? '',
              onChange: (name) => setState(() {
                _bikeId = _bikes.firstWhere((b) => b.name == name).id;
              }),
            )
          else
            const AppCard(
              padding: EdgeInsets.all(16),
              child: Text(
                'No bike loaded — this ride will count toward your primary bike.',
                style:
                    TextStyle(fontSize: 13, color: AppColors.mutedForeground),
              ),
            ),
          const SizedBox(height: 12),
          _Picker(
            label: 'Privacy',
            options: privacyOpts,
            value: privacy,
            onChange: (v) => setState(() => privacy = v),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LabelMono('Route'),
                const SizedBox(height: 4),
                const Text('No route selected',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.v, required this.u, required this.l});

  final String v;
  final String u;
  final String l;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabelMono(l),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: v, style: displayStyle(size: 20)),
                if (u.isNotEmpty)
                  TextSpan(
                      text: ' $u',
                      style: displayStyle(
                          size: 12, color: AppColors.mutedForeground)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.options,
    required this.value,
    required this.onChange,
  });

  final String label;
  final List<String> options;
  final String value;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabelMono(label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((o) {
              final on = value == o;
              return GestureDetector(
                onTap: () => onChange(o),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: on ? AppColors.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: on
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    o,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: on
                          ? AppColors.accentForeground
                          : AppColors.mutedForeground,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
