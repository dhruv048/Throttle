import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../format.dart';
import '../../models/models.dart';
import '../../theme.dart';
import '../share_card.dart';
import '../../units.dart';

/// A motorcycle's dash: top speed on a speedometer (with the average marked
/// on its dial), the distance on an odometer, and the trip underneath.
class CockpitCard extends StatelessWidget {
  const CockpitCard({super.key, required this.item, required this.design});

  final FeedItem item;
  final ShareCardDesign design;

  static const _gauge = 224.0;
  static const _gaugeTop = 120.0;

  @override
  Widget build(BuildContext context) {
    final r = item.ride;
    final backdrop = showsPhoto(item, design) || showsMap(item, design);
    final third = item.bikeText != null
        ? ('Bike', item.bikeText!)
        : item.riderText != null
            ? ('Rider', item.riderText!)
            : ('Date', item.dateText ?? '—');
    final started = item.startedLocal;

    return Stack(
      fit: StackFit.expand,
      children: [
        ShareCardBackground(
          item: item,
          design: design,
          plain: _plain(),
          // The route runs behind the dial, showing round its edges.
          mapPadding: const EdgeInsets.fromLTRB(24, 90, 24, 80),
        ),
        if (backdrop)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.6),
                  Colors.black.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.5),
                  Colors.black.withValues(alpha: 0.9),
                  Colors.black.withValues(alpha: 0.96),
                ],
                stops: const [0, 0.24, 0.45, 0.68, 1],
              ),
            ),
          ),
        Positioned(
          top: 18,
          left: 20,
          right: 20,
          child: Row(
            children: [
              const ThrottleMark(size: 15),
              const Spacer(),
              if (item.dateText != null)
                Text(
                  item.dateText!.toUpperCase(),
                  style: labelMono(size: 10, color: Colors.white).copyWith(
                      letterSpacing: 1.6, fontWeight: FontWeight.w500),
                ),
            ],
          ),
        ),
        Positioned(
          top: 48,
          left: 20,
          right: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.headline.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: displayStyle(size: 20, color: Colors.white)
                    .copyWith(letterSpacing: 0.4),
              ),
              if (item.placesText != null) ...[
                const SizedBox(height: 4),
                Text(item.placesText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelMono(
                        size: 10.5,
                        color: Colors.white.withValues(alpha: 0.75))),
              ],
            ],
          ),
        ),
        Positioned(
          top: _gaugeTop,
          left: 0,
          right: 0,
          child: Center(
            child: SizedBox.square(
              dimension: _gauge,
              child: _Speedometer(
                  top: context.units.speed(r.maxSpeedKmh),
                  avg: context.units.speed(r.avgSpeedKmh)),
            ),
          ),
        ),
        Positioned(
          top: _gaugeTop + _gauge + 14,
          left: 20,
          right: 20,
          child: Center(
              child: _Odometer(km: context.units.distance(r.distanceKm))),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 16,
          child: IntrinsicHeight(
            child: Row(
              children: [
                _stat('Ride time', formatDuration(r.movingTimeSecs)),
                _divider(),
                r.elevationM > 0
                    ? _stat('Climb', '${formatNumber(r.elevationM.round())} m')
                    : _stat(
                        'Started', started == null ? '—' : clockText(started)),
                _divider(),
                _stat(third.$1, third.$2),
              ],
            ),
          ),
        ),
        if (showsMap(item, design))
          const Positioned(right: 8, bottom: 3, child: OsmCredit()),
      ],
    );
  }

  Widget _divider() => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: Colors.white.withValues(alpha: 0.16),
      );

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                maxLines: 1,
                style: displayStyle(size: 18, color: Colors.white)),
          ),
          const SizedBox(height: 4),
          Text(label.toUpperCase(),
              style: labelMono(
                      size: 8, color: Colors.white.withValues(alpha: 0.55))
                  .copyWith(letterSpacing: 1.4)),
        ],
      ),
    );
  }

  /// Night-dark, with the dial lit from behind.
  Widget _plain() => Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF22242A), Color(0xFF0B0C0F)],
              ),
            ),
          ),
          CustomPaint(
              painter: TopoPainter(
                  color: Colors.white.withValues(alpha: 0.035), seed: 11)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, 0.02),
                radius: 0.62,
                colors: [
                  AppColors.primary.withValues(alpha: 0.28),
                  AppColors.primary.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
      );
}

/// The dial: top speed as the lit arc and the big readout, the average as a
/// marker on the scale.
class _Speedometer extends StatelessWidget {
  const _Speedometer({required this.top, required this.avg});

  final double top;
  final double avg;

  @override
  Widget build(BuildContext context) {
    final max = _scaleMax(top);
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _DialPainter(
            top: top,
            avg: avg,
            max: max,
            step: _majorStep(max),
            labelStyle: labelMono(size: 9, color: Colors.white)
                .copyWith(fontWeight: FontWeight.w500, letterSpacing: 0),
          ),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 6),
            Text('${top.round()}',
                style: displayStyle(
                        size: 54, color: Colors.white, weight: FontWeight.w700)
                    .copyWith(
                  shadows: [
                    Shadow(
                        color: heatColors[1].withValues(alpha: 0.5),
                        blurRadius: 18),
                  ],
                )),
            const SizedBox(height: 2),
            Text(context.units.speedUnit.toUpperCase(),
                style: labelMono(
                        size: 9.5, color: Colors.white.withValues(alpha: 0.6))
                    .copyWith(letterSpacing: 2.4)),
            const SizedBox(height: 3),
            Text('TOP SPEED',
                style: labelMono(size: 8, color: heatColors[1])
                    .copyWith(letterSpacing: 1.6, fontWeight: FontWeight.w500)),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 22,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('AVG ',
                  style: labelMono(
                          size: 8, color: Colors.white.withValues(alpha: 0.55))
                      .copyWith(letterSpacing: 1.4)),
              Text('${avg.round()}',
                  style: displayStyle(size: 16, color: Colors.white)),
              Text(' ${context.units.speedUnit}',
                  style: displayStyle(
                      size: 10, color: Colors.white.withValues(alpha: 0.6))),
            ],
          ),
        ),
      ],
    );
  }

  /// A round number a little above [top], so the arc reads as fast without
  /// pinning the needle.
  static double _scaleMax(double top) {
    for (final m in [40, 60, 80, 100, 120, 140, 160, 180, 200, 240, 280, 320]) {
      if (m >= top * 1.12) return m.toDouble();
    }
    return ((top * 1.12) / 50).ceil() * 50.0;
  }

  /// Labelled every [_majorStep], 4 to 7 labels round the dial.
  static double _majorStep(double max) {
    for (final s in [10, 20, 25, 30, 40, 50, 60, 80, 100]) {
      if (max % s == 0 && max / s <= 7) return s.toDouble();
    }
    return max / 5;
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.top,
    required this.avg,
    required this.max,
    required this.step,
    required this.labelStyle,
  });

  final double top;
  final double avg;
  final double max;
  final double step;
  final TextStyle labelStyle;

  static const _start = math.pi * 3 / 4;
  static const _sweep = math.pi * 3 / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final faceR = size.width / 2;
    final face = Rect.fromCircle(center: c, radius: faceR);

    canvas.drawCircle(
      c + const Offset(0, 8),
      faceR,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawCircle(
      c,
      faceR,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF2C2F37), Color(0xFF16171B), Color(0xFF0A0B0D)],
          stops: [0, 0.74, 1],
        ).createShader(face),
    );
    canvas.drawCircle(
      c,
      faceR - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.38),
            Colors.white.withValues(alpha: 0.04),
          ],
        ).createShader(face),
    );

    final arcR = faceR - 22;
    final arc = Rect.fromCircle(center: c, radius: arcR);
    canvas.drawArc(
      arc,
      _start,
      _sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = Colors.white.withValues(alpha: 0.08),
    );

    final f = (top / max).clamp(0.0, 1.0);
    if (f > 0) {
      // The scale's colour at each speed, so the tip's colour says how fast.
      final heat = const SweepGradient(
        endAngle: _sweep,
        colors: heatColors,
        transform: GradientRotation(_start),
      ).createShader(arc);
      canvas.drawArc(
        arc,
        _start,
        _sweep * f,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..shader = heat
          ..color = const Color(0x8C000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawArc(
        arc,
        _start,
        _sweep * f,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..shader = heat,
      );
      final tip = c + _dir(_start + _sweep * f) * arcR;
      canvas.drawCircle(
        tip,
        10,
        Paint()
          ..color = heatColor(f).withValues(alpha: 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(tip, 5, Paint()..color = Colors.white);
    }

    final tickOuter = arcR - 9;
    final minor = step / 2;
    for (var i = 0; i * minor <= max + 1e-6; i++) {
      final v = i * minor;
      final major = i.isEven;
      final lit = v <= top;
      final d = _dir(_start + _sweep * v / max);
      final len = major ? 9.0 : 5.0;
      canvas.drawLine(
        c + d * tickOuter,
        c + d * (tickOuter - len),
        Paint()
          ..strokeWidth = major ? 2 : 1.2
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(
              alpha: lit ? (major ? 0.9 : 0.55) : (major ? 0.35 : 0.18)),
      );
      if (major) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${v.round()}',
            style: labelStyle.copyWith(
                color: Colors.white.withValues(alpha: lit ? 0.85 : 0.4)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final at = c + d * (tickOuter - len - 11);
        tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // The average, as a marker pointing in at the scale.
    final d = _dir(_start + _sweep * (avg / max).clamp(0.0, 1.0));
    final n = Offset(-d.dy, d.dx);
    final point = c + d * (arcR + 5);
    final base = c + d * (arcR + 13);
    canvas.drawPath(
      Path()
        ..moveTo(point.dx, point.dy)
        ..lineTo((base + n * 4.5).dx, (base + n * 4.5).dy)
        ..lineTo((base - n * 4.5).dx, (base - n * 4.5).dy)
        ..close(),
      Paint()..color = Colors.white,
    );
  }

  static Offset _dir(double a) => Offset(math.cos(a), math.sin(a));

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      old.top != top || old.avg != avg || old.max != max;
}

/// The distance on drums: whole kilometres in white on black, tenths in
/// orange, leading zeros dimmed.
class _Odometer extends StatelessWidget {
  const _Odometer({required this.km});

  final double km;

  @override
  Widget build(BuildContext context) {
    final tenths = (km * 10).round();
    final whole = (tenths ~/ 10).toString().padLeft(4, '0');
    final zeros =
        whole.length - whole.replaceFirst(RegExp(r'^0+(?=\d)'), '').length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('TRIP',
            style:
                labelMono(size: 8, color: Colors.white.withValues(alpha: 0.55))
                    .copyWith(letterSpacing: 1.6)),
        const SizedBox(width: 10),
        for (var i = 0; i < whole.length; i++) _drum(whole[i], dim: i < zeros),
        const SizedBox(width: 3),
        _drum('${tenths % 10}', tenth: true),
        const SizedBox(width: 8),
        Text(context.units.distanceUnit,
            style: displayStyle(
                size: 14, color: Colors.white.withValues(alpha: 0.75))),
      ],
    );
  }

  Widget _drum(String digit, {bool dim = false, bool tenth = false}) {
    return Container(
      width: 21,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: tenth
              ? const [Color(0xFF9E3C14), Color(0xFFFF8A3D), Color(0xFF9E3C14)]
              : const [Color(0xFF040405), Color(0xFF2C2D33), Color(0xFF040405)],
        ),
      ),
      child: Text(
        digit,
        style: GoogleFonts.robotoMono(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1,
          color: Colors.white.withValues(alpha: dim ? 0.3 : 1),
        ),
      ),
    );
  }
}
