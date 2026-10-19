import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show Marker;
import 'package:latlong2/latlong.dart' show LatLng;

import '../theme.dart';

/// A ride's flag on a map: planted at [at] (its pole's foot on the point),
/// the furthest place the ride reached.
Marker flagMarker(
  ({double lat, double lng}) at, {
  double size = 30,
  bool selected = false,
  VoidCallback? onTap,
  Key? key,
}) {
  final s = selected ? size * 1.35 : size;
  return Marker(
    key: key,
    point: LatLng(at.lat, at.lng),
    width: s,
    height: s,
    // The pole's foot, not the marker's middle, is on the point.
    alignment: Marker.computePixelAlignment(
        width: s, height: s, left: s * FlagPainter.poleX, top: s * 0.96),
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: PlantedFlag(size: s, outlined: true),
    ),
  );
}

/// A flag on a pole, still (on maps) or waving in the wind.
class PlantedFlag extends StatefulWidget {
  const PlantedFlag({
    super.key,
    this.size = 30,
    this.waving = false,
    this.outlined = false,
    this.color = AppColors.primary,
    this.poleColor = AppColors.foreground,
    this.raise,
  });

  final double size;

  /// Ripples in the wind (unless the rider asked for reduced motion).
  final bool waving;

  /// A white edge, to stand out on a map.
  final bool outlined;
  final Color color;
  final Color poleColor;

  /// Drives it being planted, 0 → 1: the pole goes up, then the flag
  /// unfurls. Fully planted when null.
  final Animation<double>? raise;

  @override
  State<PlantedFlag> createState() => _PlantedFlagState();
}

class _PlantedFlagState extends State<PlantedFlag>
    with SingleTickerProviderStateMixin {
  AnimationController? _wind;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.waving && !still) {
      _wind ??= AnimationController(
          vsync: this, duration: const Duration(milliseconds: 1400))
        ..repeat();
    } else {
      _wind?.dispose();
      _wind = null;
    }
  }

  @override
  void dispose() {
    _wind?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wind = _wind;
    final raise = widget.raise;
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: FlagPainter(
          wind: wind,
          raise: raise,
          color: widget.color,
          poleColor: widget.poleColor,
          outlined: widget.outlined,
        ),
      ),
    );
  }
}

/// Paints a flag in a square: the pole up its left side, the cloth flying
/// right from the top, rippling with [wind].
class FlagPainter extends CustomPainter {
  FlagPainter({
    this.wind,
    this.raise,
    required this.color,
    required this.poleColor,
    this.outlined = false,
  }) : super(repaint: Listenable.merge([wind, raise]));

  /// Where the pole stands, across the square.
  static const poleX = 0.2;

  final Animation<double>? wind;
  final Animation<double>? raise;
  final Color color;
  final Color poleColor;
  final bool outlined;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final t = raise?.value ?? 1;
    // The pole rises over the first half, the cloth unfurls over the rest.
    final pole = Curves.easeOutBack.transform((t / 0.5).clamp(0, 1));
    final unfurl = Curves.easeOutCubic.transform(((t - 0.4) / 0.6).clamp(0, 1));
    final phase = (wind?.value ?? 0.15) * 2 * math.pi;
    final waveAmp = wind == null ? s * 0.025 : s * 0.045;

    final foot = Offset(s * poleX, s * 0.96);
    final top = Offset(foot.dx, foot.dy - s * 0.9 * pole);
    final poleW = math.max(1.5, s * 0.065);

    // The ground it's planted in.
    canvas.drawOval(
      Rect.fromCenter(center: foot, width: s * 0.34, height: s * 0.09),
      Paint()..color = Colors.black.withValues(alpha: 0.18 * pole),
    );

    if (unfurl > 0) {
      final w = s * 0.7 * unfurl;
      final h = s * 0.46;
      final x0 = top.dx + poleW / 2 - 0.5;
      final y0 = top.dy + s * 0.02;
      double wave(double x) =>
          math.sin(x / (s * 0.7) * 2.2 * math.pi - phase) *
          waveAmp *
          (x / (s * 0.7));
      final cloth = Path()..moveTo(x0, y0);
      const steps = 14;
      for (var i = 1; i <= steps; i++) {
        final x = w * i / steps;
        cloth.lineTo(x0 + x, y0 + wave(x));
      }
      for (var i = steps; i >= 0; i--) {
        final x = w * i / steps;
        cloth.lineTo(x0 + x, y0 + h + wave(x));
      }
      cloth.close();
      if (outlined) {
        canvas.drawPath(
          cloth,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(2, s * 0.08)
            ..strokeJoin = StrokeJoin.round,
        );
      }
      canvas.drawPath(cloth, Paint()..color = color);
      // Light catching the folds.
      canvas.save();
      canvas.clipPath(cloth);
      final shade = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.22),
            Colors.black.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.16),
            Colors.black.withValues(alpha: 0.12),
          ],
          stops: const [0, 0.35, 0.6, 1],
          transform: GradientRotation(math.sin(phase) * 0.15),
        ).createShader(Rect.fromLTWH(x0, y0 - waveAmp, w, h + 2 * waveAmp));
      canvas.drawRect(Rect.fromLTWH(x0, y0 - s, w + s, h + 2 * s), shade);
      canvas.restore();
    }

    final polePaint = Paint()
      ..color = poleColor
      ..strokeWidth = poleW
      ..strokeCap = StrokeCap.round;
    if (outlined) {
      canvas.drawLine(
        foot,
        top,
        Paint()
          ..color = Colors.white
          ..strokeWidth = poleW + math.max(2, s * 0.08)
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawLine(foot, top, polePaint);
    // The finial.
    canvas.drawCircle(top, poleW * 0.9, Paint()..color = poleColor);
  }

  @override
  bool shouldRepaint(covariant FlagPainter old) =>
      old.wind != wind ||
      old.raise != raise ||
      old.color != color ||
      old.poleColor != poleColor ||
      old.outlined != outlined;
}
