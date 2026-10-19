import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';

/// At most [max] of [track]'s points, evenly spaced, always keeping the last.
List<TrackPoint> downsampleTrack(List<TrackPoint> track, int max) {
  final step = (track.length / max).ceil().clamp(1, track.length);
  return [
    for (var i = 0; i < track.length; i += step) track[i],
    if ((track.length - 1) % step != 0) track.last,
  ];
}

/// [track] projected onto [size], north up, scaled to fit inside [padding]
/// and centred.
List<Offset> fitTrack(List<TrackPoint> track, Size size,
    {EdgeInsets padding = EdgeInsets.zero}) {
  var minLat = track.first.lat, maxLat = minLat;
  var minLng = track.first.lng, maxLng = minLng;
  for (final p in track) {
    minLat = math.min(minLat, p.lat);
    maxLat = math.max(maxLat, p.lat);
    minLng = math.min(minLng, p.lng);
    maxLng = math.max(maxLng, p.lng);
  }
  // Equirectangular: shrink longitude by cos(lat) so shapes aren't stretched.
  final lngScale = math.cos((minLat + maxLat) / 2 * math.pi / 180);
  final spanX = math.max((maxLng - minLng) * lngScale, 1e-6);
  final spanY = math.max(maxLat - minLat, 1e-6);
  final w = size.width - padding.horizontal;
  final h = size.height - padding.vertical;
  final scale = math.min(w / spanX, h / spanY);
  final offX = padding.left + (w - spanX * scale) / 2;
  final offY = padding.top + (h - spanY * scale) / 2;
  return [
    for (final p in track)
      Offset(
        offX + (p.lng - minLng) * lngScale * scale,
        offY + (maxLat - p.lat) * scale,
      ),
  ];
}

/// Speed along each of [track]'s segments in km/h, smoothed over a few
/// segments so GPS jitter doesn't show. Null when the track has no times.
List<double>? trackSpeedsKmh(List<TrackPoint> track) {
  if (track.length < 2 || track.any((p) => p.t == null)) return null;
  final raw = <double>[];
  for (var i = 1; i < track.length; i++) {
    final secs = track[i].t!.difference(track[i - 1].t!).inMilliseconds / 1000;
    raw.add(secs <= 0 ? 0 : _metres(track[i - 1], track[i]) / secs * 3.6);
  }
  const half = 2;
  return [
    for (var i = 0; i < raw.length; i++)
      _mean(raw.sublist(
          math.max(0, i - half), math.min(raw.length, i + half + 1))),
  ];
}

double _mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;

double _metres(TrackPoint a, TrackPoint b) {
  const r = 6371000.0;
  final dLat = (b.lat - a.lat) * math.pi / 180;
  final dLng = (b.lng - a.lng) * math.pi / 180;
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(a.lat * math.pi / 180) *
          math.cos(b.lat * math.pi / 180) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// Draws a GPS track's shape (no map), scaled to fit. Used for the route
/// trace on share images.
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
    final pts = fitTrack(downsampleTrack(track, _maxPoints), size,
        padding: EdgeInsets.all(padding));
    final path = Path()..addPolygon(pts, false);

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
    canvas.drawCircle(pts.first, dot, Paint()..color = startColor);
    canvas.drawCircle(pts.last, dot, Paint()..color = endColor);
    canvas.drawCircle(pts.last, dot * 0.45, Paint()..color = casingColor);
  }

  @override
  bool shouldRepaint(covariant TrackShapePainter oldDelegate) =>
      !identical(oldDelegate.track, track) ||
      oldDelegate.lineColor != lineColor;
}
