import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../format.dart';
import '../../models/models.dart';
import '../../theme.dart';
import '../share_card.dart';
import '../track_shape.dart';
import '../../units.dart';

/// The route as the hero: glowing, coloured by how fast each stretch was,
/// with where the rider hit top speed called out.
class TraceCard extends StatelessWidget {
  const TraceCard({super.key, required this.item, required this.design});

  final FeedItem item;
  final ShareCardDesign design;

  @override
  Widget build(BuildContext context) {
    final r = item.ride;
    final units = context.units;
    final photo = showsPhoto(item, design);
    final map = showsMap(item, design);
    final hasTrack = item.points.length >= 2;
    final started = item.startedLocal;
    final meta = [
      if (item.dayText != null) item.dayText!,
      if (started != null) clockText(started),
      if (item.placesText != null) item.placesText!,
    ].join('  ·  ');
    final footer = [
      if (item.riderText != null) item.riderText!,
      if (item.bikeText != null) item.bikeText!,
    ].join('  ·  ');

    return Stack(
      fit: StackFit.expand,
      children: [
        ShareCardBackground(
          item: item,
          design: design,
          plain: _plain(),
          // The route fills the middle, between the headline and the stats.
          mapPadding: const EdgeInsets.fromLTRB(36, 112, 36, 150),
          darkMap: true,
        ),
        if (photo) ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
        if (photo || map)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.72),
                  Colors.black.withValues(alpha: 0),
                  Colors.black.withValues(alpha: 0),
                  Colors.black.withValues(alpha: 0.92),
                ],
                stops: const [0, 0.3, 0.6, 0.86],
              ),
            ),
          ),
        Positioned(
          top: 22,
          left: 22,
          right: 22,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.headline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: displayStyle(size: 28, color: Colors.white)
                    .copyWith(height: 1.08),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(meta.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelMono(
                            size: 9.5,
                            color: Colors.white.withValues(alpha: 0.7))
                        .copyWith(letterSpacing: 1.2)),
              ],
            ],
          ),
        ),
        if (!map)
          Positioned(
            left: 16,
            right: 16,
            top: 100,
            bottom: 128,
            child: hasTrack
                ? CustomPaint(
                    painter: _GlowRoutePainter(
                      item.points,
                      top: units.speed(r.maxSpeedKmh),
                      unit: units.speedUnit,
                      valueStyle: displayStyle(size: 15, color: Colors.white),
                      unitStyle: displayStyle(
                          size: 9, color: Colors.white.withValues(alpha: 0.7)),
                      captionStyle: labelMono(
                              size: 6.5,
                              color: Colors.white.withValues(alpha: 0.65))
                          .copyWith(letterSpacing: 1.2),
                    ),
                  )
                : _bigDistance(units, r.distanceKm),
          ),
        Positioned(
          left: 22,
          right: 22,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasTrack || map)
                    _stat('Distance', units.short(r.distanceKm),
                        units.distanceUnit),
                  _stat('Time', formatDuration(r.movingTimeSecs)),
                  _stat('Avg speed', '${units.speed(r.avgSpeedKmh).round()}',
                      units.speedUnit),
                  _stat('Top speed', '${units.speed(r.maxSpeedKmh).round()}',
                      units.speedUnit, heatColors[1]),
                ],
              ),
              const SizedBox(height: 14),
              Container(height: 1, color: Colors.white.withValues(alpha: 0.14)),
              const SizedBox(height: 10),
              Row(
                children: [
                  const ThrottleMark(size: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(footer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: labelMono(
                                size: 9.5,
                                color: Colors.white.withValues(alpha: 0.65))
                            .copyWith(letterSpacing: 0.4)),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (map) const Positioned(right: 8, bottom: 3, child: OsmCredit()),
      ],
    );
  }

  Widget _bigDistance(Units units, double km) => Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(units.short(km),
                  style: displayStyle(
                      size: 120, color: Colors.white, weight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text(units.distanceUnit.toUpperCase(),
                  style: displayStyle(size: 30, color: heatColors[1])),
            ],
          ),
        ),
      );

  Widget _stat(String label, String value, [String? unit, Color? color]) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: value),
                if (unit != null)
                  TextSpan(
                      text: ' $unit',
                      style: displayStyle(
                          size: 11,
                          color: Colors.white.withValues(alpha: 0.6))),
              ]),
              maxLines: 1,
              style: displayStyle(size: 22, color: color ?? Colors.white),
            ),
          ),
          const SizedBox(height: 4),
          Text(label.toUpperCase(),
              style: labelMono(
                      size: 7.5, color: Colors.white.withValues(alpha: 0.55))
                  .copyWith(letterSpacing: 1.3)),
        ],
      ),
    );
  }

  /// Near-black, with a warm glow where the route is.
  Widget _plain() => Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF17181D), Color(0xFF0B0C0E)],
              ),
            ),
          ),
          CustomPaint(
              painter: TopoPainter(
                  color: Colors.white.withValues(alpha: 0.04), seed: 9)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.05),
                radius: 0.7,
                colors: [
                  heatColors[1].withValues(alpha: 0.16),
                  heatColors[1].withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
      );
}

/// The route as a neon tube: a soft glow, then the line coloured slow (amber)
/// to fast (red), and a tag where the rider hit top speed. Without times
/// the colour runs from start to finish instead.
class _GlowRoutePainter extends CustomPainter {
  _GlowRoutePainter(
    this.track, {
    required this.top,
    required this.unit,
    required this.valueStyle,
    required this.unitStyle,
    required this.captionStyle,
  });

  final List<TrackPoint> track;

  /// Top speed, in [unit]s.
  final double top;
  final String unit;
  final TextStyle valueStyle;
  final TextStyle unitStyle;
  final TextStyle captionStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final sampled = downsampleTrack(track, 300);
    final pts = fitTrack(sampled, size, padding: const EdgeInsets.all(18));
    final speeds = trackSpeedsKmh(sampled);
    final path = Path()..addPolygon(pts, false);

    Paint stroke(double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
        path,
        stroke(20)
          ..color = heatColors[1].withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.drawPath(
        path,
        stroke(8)
          ..color = heatColors[1].withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));

    final List<double> heat;
    if (speeds != null) {
      final sorted = [...speeds]..sort();
      final lo = sorted[(sorted.length * 0.1).floor()];
      final hi =
          sorted[math.min(sorted.length - 1, (sorted.length * 0.95).floor())];
      heat = [for (final s in speeds) hi > lo ? (s - lo) / (hi - lo) : 0.5];
    } else {
      heat = [for (var i = 0; i < pts.length - 1; i++) i / (pts.length - 1)];
    }
    for (var i = 0; i < pts.length - 1; i++) {
      canvas.drawLine(
          pts[i], pts[i + 1], stroke(3.6)..color = heatColor(heat[i]));
    }
    canvas.drawPath(
        path, stroke(1.1)..color = Colors.white.withValues(alpha: 0.3));

    canvas.drawCircle(pts.first, 6, Paint()..color = Colors.white);
    canvas.drawCircle(pts.first, 2.6, Paint()..color = const Color(0xFF111215));
    canvas.drawCircle(pts.last, 6.5, Paint()..color = heatColors[2]);
    canvas.drawCircle(pts.last, 2.6, Paint()..color = Colors.white);

    if (speeds != null) _topSpeedTag(canvas, size, pts, speeds);
  }

  /// A tag on the fastest stretch, nudged to stay on the canvas.
  void _topSpeedTag(
      Canvas canvas, Size size, List<Offset> pts, List<double> speeds) {
    var i = 0;
    for (var j = 1; j < speeds.length; j++) {
      if (speeds[j] > speeds[i]) i = j;
    }
    final at = (pts[i] + pts[i + 1]) / 2;
    canvas.drawCircle(
        at,
        10,
        Paint()
          ..color = heatColors[2].withValues(alpha: 0.65)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(at, 4.2, Paint()..color = Colors.white);

    final caption = TextPainter(
      text: TextSpan(text: 'TOP SPEED', style: captionStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final value = TextPainter(
      text: TextSpan(children: [
        TextSpan(text: '${top.round()}', style: valueStyle),
        TextSpan(text: ' $unit', style: unitStyle),
      ]),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = Size(math.max(caption.width, value.width) + 16,
        caption.height + value.height + 11);
    // Outside the loop of the route, away from its middle, joined to the
    // point by a short line.
    final middle = pts.reduce((a, b) => a + b) / pts.length.toDouble();
    final out = at - middle;
    final origin = Offset(
      (out.dx >= 0 ? at.dx + 18 : at.dx - 18 - box.width)
          .clamp(0.0, size.width - box.width),
      (out.dy >= 0 ? at.dy + 14 : at.dy - 14 - box.height)
          .clamp(0.0, size.height - box.height),
    );
    final rect = origin & box;
    final near = Offset(
        at.dx.clamp(rect.left, rect.right), at.dy.clamp(rect.top, rect.bottom));
    canvas.drawLine(
        at,
        near,
        Paint()
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.6));
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(7));
    canvas.drawRRect(rrect,
        Paint()..color = const Color(0xFF0B0C0E).withValues(alpha: 0.82));
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = heatColors[2].withValues(alpha: 0.8));
    caption.paint(canvas, origin + const Offset(8, 5));
    value.paint(canvas, origin + Offset(8, 6 + caption.height));
  }

  @override
  bool shouldRepaint(covariant _GlowRoutePainter old) =>
      !identical(old.track, track) || old.top != top;
}
