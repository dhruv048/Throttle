import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../data.dart';
import '../models/models.dart';
import '../theme.dart';

class RouteMap extends StatelessWidget {
  const RouteMap({
    super.key,
    this.seed = 0,
    this.height = 128,
    this.label,
    this.track,
  });

  final int seed;

  /// Real GPS track; when given (2+ points) it is drawn instead of the
  /// seeded placeholder squiggle.
  final List<TrackPoint>? track;
  final double height;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Positioned.fill(
            child: CustomPaint(
              painter: (track?.length ?? 0) >= 2
                  ? TrackShapePainter(track!)
                  : _RoutePainter(seed: seed),
            ),
          ),
          if (label != null)
            Positioned(
              left: 12,
              top: 8,
              child: Text(
                label!.toUpperCase(),
                style: labelMono(color: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.panel);
    final paint = Paint()
      ..color = AppColors.grid
      ..strokeWidth = 1;
    const step = 22.0;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = routePoints(seed, w: size.width, h: size.height);
    final path = routePathFromPoints(pts);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.card
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.seed != seed;
}

/// Draws a GPS track's shape (no map), scaled to fit. Used for grid
/// previews and the route trace on share images.
class TrackShapePainter extends CustomPainter {
  TrackShapePainter(
    this.track, {
    this.lineColor = AppColors.primary,
    this.casingColor = AppColors.card,
    this.startColor = AppColors.foreground,
    this.endColor = AppColors.primary,
    this.strokeWidth = 3.5,
    this.padding = 18,
    this.shadow = false,
  });

  final List<TrackPoint> track;
  final Color lineColor;
  final Color casingColor;
  final Color startColor;
  final Color endColor;
  final double strokeWidth;
  final double padding;
  final bool shadow;
  static const _maxPoints = 200;

  @override
  void paint(Canvas canvas, Size size) {
    final step = (track.length / _maxPoints).ceil().clamp(1, track.length);
    final pts = [
      for (var i = 0; i < track.length; i += step) track[i],
      if ((track.length - 1) % step != 0) track.last,
    ];

    var minLat = pts.first.lat, maxLat = minLat;
    var minLng = pts.first.lng, maxLng = minLng;
    for (final p in pts) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    // Equirectangular: shrink longitude by cos(lat) so shapes aren't stretched.
    final lngScale = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    final spanX = math.max((maxLng - minLng) * lngScale, 1e-6);
    final spanY = math.max(maxLat - minLat, 1e-6);
    final w = size.width - padding * 2;
    final h = size.height - padding * 2;
    final scale = math.min(w / spanX, h / spanY);
    final offX = padding + (w - spanX * scale) / 2;
    final offY = padding + (h - spanY * scale) / 2;

    Offset project(TrackPoint p) => Offset(
          offX + (p.lng - minLng) * lngScale * scale,
          offY + (maxLat - p.lat) * scale,
        );

    final path = Path()..moveTo(project(pts.first).dx, project(pts.first).dy);
    for (final p in pts.skip(1)) {
      final o = project(p);
      path.lineTo(o.dx, o.dy);
    }

    if (shadow) {
      canvas.drawPath(
        path.shift(const Offset(0, 1.5)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth * 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = casingColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final dot = strokeWidth * 1.3;
    canvas.drawCircle(project(pts.first), dot, Paint()..color = startColor);
    canvas.drawCircle(project(pts.last), dot, Paint()..color = endColor);
    canvas.drawCircle(
        project(pts.last), dot * 0.45, Paint()..color = casingColor);
  }

  @override
  bool shouldRepaint(covariant TrackShapePainter oldDelegate) =>
      !identical(oldDelegate.track, track) ||
      oldDelegate.lineColor != lineColor;
}
