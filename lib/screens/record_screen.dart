import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../data.dart';
import '../theme.dart';
import '../widgets/route_map.dart';
import '../widgets/ui.dart';

enum RideStatus { idle, riding, paused, done }

const privacyOpts = ['Public', 'Followers', 'Private'];

double haversine(Position a, Position b) {
  const r = 6371.0;
  double toR(double d) => d * math.pi / 180;
  final dLat = toR(b.latitude - a.latitude);
  final dLon = toR(b.longitude - a.longitude);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(toR(a.latitude)) * math.cos(toR(b.latitude)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.asin(math.sqrt(h));
}

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
  int secs = 0;
  double km = 0;
  int speed = 0;
  int top = 0;
  String gps = 'Searching GPS…';
  late String bike;
  String privacy = 'Followers';
  Position? last;
  StreamSubscription<Position>? watch;
  Timer? ticker;

  @override
  void initState() {
    super.initState();
    bike = me.bikes.first.name;
    _startGps();
  }

  Future<void> _startGps() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (mounted) setState(() => gps = 'GPS unavailable');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => gps = 'Allow location to track');
      return;
    }
    watch = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0),
    ).listen(
      (p) {
        if (!mounted) return;
        setState(() {
          gps = 'GPS locked · ±${p.accuracy.round()} m';
          final raw = p.speed;
          final mps = (raw.isNaN || raw < 0) ? 0.0 : raw;
          final kmh = (mps * 3.6).round();
          speed = kmh;
          top = math.max(top, kmh);
          if (status == RideStatus.riding && last != null) {
            km += haversine(last!, p);
          }
          last = p;
        });
      },
      onError: (_) {
        if (mounted) setState(() => gps = 'Allow location to track');
      },
    );
  }

  void _setStatus(RideStatus next) {
    ticker?.cancel();
    setState(() => status = next);
    if (next == RideStatus.riding) {
      ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => secs += 1);
      });
    }
  }

  void _reset() {
    ticker?.cancel();
    setState(() {
      status = RideStatus.idle;
      secs = 0;
      km = 0;
      top = 0;
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    watch?.cancel();
    super.dispose();
  }

  int get avg => secs > 0 ? (km / (secs / 3600)).round() : 0;

  @override
  Widget build(BuildContext context) {
    if (status == RideStatus.done) {
      return ListView(
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
                      RouteMap(seed: secs + 3, height: 160),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(
                          runSpacing: 16,
                          children: [
                            SizedBox(
                              width: MediaQuery.sizeOf(context).width / 2 - 32,
                              child: StatBlock(value: km.toStringAsFixed(1), label: 'km', valueSize: 30),
                            ),
                            SizedBox(
                              width: MediaQuery.sizeOf(context).width / 2 - 32,
                              child: StatBlock(value: fmt(secs), label: 'moving time', valueSize: 30),
                            ),
                            SizedBox(
                              width: MediaQuery.sizeOf(context).width / 2 - 32,
                              child: StatBlock(value: '$avg', label: 'avg km/h', valueSize: 30),
                            ),
                            SizedBox(
                              width: MediaQuery.sizeOf(context).width / 2 - 32,
                              child: StatBlock(value: '$top', label: 'top km/h', valueSize: 30),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: AppColors.border)),
                        ),
                        child: Text('$bike · $privacy', style: monoStyle(size: 11, tracking: 0)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _reset,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('SHARE RIDE', style: displayStyle(size: 20, color: AppColors.primaryForeground)),
                  ),
                ),
                TextButton(
                  onPressed: _reset,
                  child: const Text('Discard', style: TextStyle(fontSize: 14, color: AppColors.mutedForeground)),
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
                      TextSpan(text: ' km/h', style: displayStyle(size: 18, color: AppColors.mutedForeground)),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: _Cell(v: km.toStringAsFixed(1), u: 'km', l: 'Distance')),
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
                      child: Text('START', style: displayStyle(size: 24, color: AppColors.primaryForeground)),
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
                              status == RideStatus.riding ? RideStatus.paused : RideStatus.riding,
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.secondary,
                              foregroundColor: AppColors.foreground,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Text('FINISH', style: displayStyle(size: 20, color: AppColors.background)),
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
          _Picker(
            label: 'Motorcycle',
            options: me.bikes.map((b) => b.name).toList(),
            value: bike,
            onChange: (v) => setState(() => bike = v),
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
                const Text('No route selected', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
                if (u.isNotEmpty) TextSpan(text: ' $u', style: displayStyle(size: 12, color: AppColors.mutedForeground)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: on ? AppColors.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: on ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border,
                    ),
                  ),
                  child: Text(
                    o,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: on ? AppColors.accentForeground : AppColors.mutedForeground,
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
