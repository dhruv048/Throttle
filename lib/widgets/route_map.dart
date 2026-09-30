import 'package:flutter/material.dart';
import '../data.dart';
import '../theme.dart';

class RouteMap extends StatelessWidget {
  const RouteMap({
    super.key,
    required this.seed,
    this.height = 128,
    this.label,
  });

  final int seed;
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
            child: CustomPaint(painter: _RoutePainter(seed: seed)),
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
  bool shouldRepaint(covariant _RoutePainter oldDelegate) => oldDelegate.seed != seed;
}
