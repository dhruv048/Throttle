import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models/models.dart';
import '../providers/recorder.dart';
import '../services/achievements.dart';
import '../services/ride_tracker.dart' show haversineM;
import '../theme.dart';
import 'badges.dart';
import 'ride_flag.dart';
import 'track_shape.dart';
import 'ui.dart';
import '../units.dart';

/// FINISH: the ride's flag is planted, with what it earned, while it saves
/// in the background. NEXT goes on to the ride's page (underneath), where
/// the rider finishes it off. It closes itself if the ride is done with.
Future<void> showRideCelebration(BuildContext context) {
  return Navigator.of(context).push(PageRouteBuilder<void>(
    // The page underneath keeps painting: it holds the ride's form.
    opaque: false,
    transitionDuration: const Duration(milliseconds: 450),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, __, ___) => const RideCelebration(),
    transitionsBuilder: (_, animation, __, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: 0.96, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  ));
}

class RideCelebration extends ConsumerStatefulWidget {
  const RideCelebration({super.key});

  @override
  ConsumerState<RideCelebration> createState() => _RideCelebrationState();
}

class _RideCelebrationState extends ConsumerState<RideCelebration>
    with SingleTickerProviderStateMixin {
  static const _night = Color(0xFF15161A);

  late final AnimationController _intro = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600));
  bool _planted = false;

  /// The ride, as last seen: it stays on screen while this closes.
  late FinishedRide _ride = ref.read(finishedRideProvider)!;

  bool _closing = false;

  /// The flag goes up, then the rest arrives in turn.
  late final Animation<double> _raise = _after(0.05, 0.45, Curves.linear);

  /// [_intro]'s stretch from [start] to [end], as 0 → 1.
  Animation<double> _after(double start, double end,
          [Curve curve = Curves.easeOutCubic]) =>
      _intro.drive(CurveTween(curve: Interval(start, end, curve: curve)));

  @override
  void initState() {
    super.initState();
    _intro.addListener(() {
      // A thud as the pole goes in.
      if (!_planted && _intro.value >= 0.24) {
        _planted = true;
        HapticFeedback.heavyImpact();
      }
    });
    // Done with (DONE, DISCARD, RESUME): close.
    ref.listenManual(finishedRideProvider, (_, next) {
      if (next == null || next.ride.localId != _ride.ride.localId) {
        _close();
      } else {
        setState(() => _ride = next);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro.isAnimating || _intro.isCompleted) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _planted = true;
      _intro.value = 1;
    } else {
      _intro.forward();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  /// How far from the start the flag went in, in km.
  double? get _reachKm {
    final points = _ride.ride.points;
    final flag = flagPoint(points);
    if (flag == null) return null;
    final km =
        haversineM(points.first.lat, points.first.lng, flag.lat, flag.lng) /
            1000;
    return km >= 0.2 ? km : null;
  }

  /// "You reached Nagarkot, 19.0 km from where you set off."
  String? get _reachLine {
    final km = _reachKm;
    final place = _ride.ride.endPlace;
    if (place != null && place != _ride.ride.startPlace) {
      return km == null
          ? 'You reached $place.'
          : 'You reached $place, ${km.toStringAsFixed(1)} km from where '
              'you set off.';
    }
    return km == null
        ? null
        : 'You reached ${km.toStringAsFixed(1)} km from where you set off.';
  }

  @override
  Widget build(BuildContext context) {
    final ride = _ride.ride;
    final achievements = _ride.achievements ?? const RideAchievements();
    final n = achievements.flagNumber;
    final reach = _reachLine;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _night,
        body: Stack(
          children: [
            if (ride.points.length >= 2)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _RouteGlowPainter(
                      downsampleTrack(ride.points, 300),
                      _after(0, 0.7, Curves.easeInOutCubic),
                    ),
                  ),
                ),
              ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: constraints.maxHeight),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 8),
                              _hero(),
                              const SizedBox(height: 20),
                              _reveal(
                                0,
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  child: Text(
                                    n == null
                                        ? 'FLAG PLANTED'
                                        : 'FLAG #$n PLANTED',
                                    key: ValueKey(n),
                                    style: labelMono(
                                            size: 12, color: AppColors.primary)
                                        .copyWith(letterSpacing: 3),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _reveal(
                                1,
                                Text('Ride complete.',
                                    textAlign: TextAlign.center,
                                    style: displayStyle(
                                        size: 46, color: Colors.white)),
                              ),
                              if (reach != null) ...[
                                const SizedBox(height: 10),
                                _reveal(
                                  1,
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 250),
                                    child: Text(
                                      reach,
                                      key: ValueKey(reach),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          height: 1.4,
                                          color: Colors.white70),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              _reveal(2, _stats()),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: Column(
                                  children: [
                                    if (achievements.earned.isNotEmpty)
                                      const SizedBox(height: 24),
                                    for (var i = 0;
                                        i < achievements.earned.length;
                                        i++)
                                      _reveal(
                                        3 + i,
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 10),
                                          child: _AchievementTile(
                                              achievements.earned[i]),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _actions(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The flag going in, with rings in the ground and confetti.
  Widget _hero() {
    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _RingsPainter(_after(0.22, 0.85, Curves.easeOut)),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ConfettiPainter(_after(0.26, 1, Curves.linear)),
              ),
            ),
          ),
          Positioned.fill(
            child: PlantedFlag(
              size: 180,
              waving: true,
              raise: _raise,
              poleColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stats() {
    final r = _ride.ride;
    final units = context.units;
    final grow = _after(0.4, 0.85);
    Widget stat(String label, String Function(double t) value) => Expanded(
          child: AnimatedBuilder(
            animation: grow,
            builder: (_, __) => Column(
              children: [
                Text(value(grow.value),
                    maxLines: 1,
                    style: displayStyle(size: 28, color: Colors.white)),
                const SizedBox(height: 4),
                LabelMono(label, color: Colors.white54),
              ],
            ),
          ),
        );
    return Row(
      children: [
        stat(units.distanceUnit, (t) => units.fixed(r.distanceKm * t, 1)),
        stat('moving', (t) => formatDuration((r.movingTimeSecs * t).round())),
        stat(
            'top speed',
            (t) =>
                '${(units.speed(r.maxSpeedKmh) * t).round()} ${units.speedUnit}'),
      ],
    );
  }

  /// [child] fades and rises in as the [i]th thing to arrive.
  Widget _reveal(int i, Widget child) {
    final start = math.min(0.42 + i * 0.07, 0.9);
    final t = _after(start, math.min(start + 0.25, 1));
    return FadeTransition(
      opacity: t,
      child: SlideTransition(
        position:
            Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(t),
        child: child,
      ),
    );
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('NEXT', style: displayStyle(size: 20, color: Colors.white)),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded,
                  color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile(this.achievement);

  final Achievement achievement;

  static const _records = {
    AchievementKind.longest: Icons.straighten_rounded,
    AchievementKind.fastest: Icons.speed_rounded,
    AchievementKind.climb: Icons.terrain_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          if (achievement.badge case final badge?)
            BadgeMedal(badge, size: 44)
          else
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(_records[achievement.kind],
                  size: 22, color: AppColors.primary),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (achievement.badge != null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: LabelMono('Badge earned', color: AppColors.primary),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: LabelMono('Personal best', color: Colors.white54),
                  ),
                Text(achievement.title,
                    style: displayStyle(size: 18, color: Colors.white)),
                const SizedBox(height: 3),
                Text(achievement.detail,
                    style: const TextStyle(
                        fontSize: 13, height: 1.3, color: Colors.white60)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The ride's route drawn faintly behind everything, traced as [progress]
/// runs.
class _RouteGlowPainter extends CustomPainter {
  _RouteGlowPainter(this.track, this.progress) : super(repaint: progress);

  final List<TrackPoint> track;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Size(size.width, size.height * 0.5);
    final points = fitTrack(track, area,
        padding: EdgeInsets.fromLTRB(
            size.width * 0.12, size.height * 0.08, size.width * 0.12, 0));
    final shown = (points.length * progress.value).ceil();
    if (shown < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < shown; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RouteGlowPainter old) =>
      old.track != track || old.progress != progress;
}

/// Rings spreading through the ground from the flag's foot.
class _RingsPainter extends CustomPainter {
  _RingsPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    final foot = Offset(size.width * FlagPainter.poleX, size.height * 0.96);
    for (final delay in const [0.0, 0.25]) {
      final r = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (r <= 0) continue;
      canvas.drawOval(
        Rect.fromCenter(
            center: foot, width: 30 + 230 * r, height: (30 + 230 * r) * 0.28),
        Paint()
          ..color = AppColors.primary.withValues(alpha: 0.55 * (1 - r))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) => old.progress != progress;
}

/// A burst of confetti from the top of the flag, falling away.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  static const _colors = [
    AppColors.primary,
    Colors.white,
    Color(0xFFFFC078),
    Color(0xFFFF8A3D),
    Color(0xFFF7EDE3),
  ];

  static final List<_Bit> _bits = () {
    final random = math.Random(7);
    return [
      for (var i = 0; i < 80; i++)
        _Bit(
          angle: -math.pi / 2 + (random.nextDouble() - 0.5) * math.pi * 1.5,
          speed: 260 + random.nextDouble() * 420,
          spin: (random.nextDouble() - 0.5) * 18,
          color: _colors[i % _colors.length],
          size: 4 + random.nextDouble() * 5,
          drift: (random.nextDouble() - 0.5) * 60,
        ),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    final origin = Offset(size.width * 0.45, size.height * 0.2);
    final secs = t * 2.2;
    const gravity = 620.0;
    final fade = t < 0.75 ? 1.0 : (1 - t) / 0.25;
    for (final b in _bits) {
      final dx = math.cos(b.angle) * b.speed * secs + b.drift * secs;
      final dy = math.sin(b.angle) * b.speed * secs +
          0.5 * gravity * secs * secs -
          // Air slows them.
          0.18 * b.speed * secs * secs;
      canvas.save();
      canvas.translate(origin.dx + dx, origin.dy + dy);
      canvas.rotate(b.spin * secs);
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset.zero, width: b.size, height: b.size * 0.5),
        Paint()..color = b.color.withValues(alpha: fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) =>
      old.progress != progress;
}

class _Bit {
  const _Bit({
    required this.angle,
    required this.speed,
    required this.spin,
    required this.color,
    required this.size,
    required this.drift,
  });

  final double angle;
  final double speed;
  final double spin;
  final Color color;
  final double size;
  final double drift;
}
