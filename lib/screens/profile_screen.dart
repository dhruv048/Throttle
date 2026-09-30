import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data.dart';
import '../theme.dart';
import '../widgets/rider_avatar.dart';
import '../widgets/ui.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      children: [
        RiseIn(
          child: Row(
            children: [
              RiderAvatar(initials: me.initials, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(me.name, style: displayStyle(size: 30)),
                    const SizedBox(height: 4),
                    Text('${me.city} · Rider since 2019', style: monoStyle(size: 11, tracking: 0)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              _col('${me.followers}', 'followers'),
              _col('${me.following}', 'following'),
              _col('${me.rides}', 'rides'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const LabelMono('Garage'),
        const SizedBox(height: 8),
        ...me.bikes.map(
          (b) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(b.name, style: displayStyle(size: 20))),
                      if (b.primary) LabelMono('Primary', color: AppColors.primary),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${b.year} · ${formatNumber(b.km)} km ridden', style: monoStyle(size: 11, tracking: 0)),
                ],
              ),
            ),
          ),
        ),
        CustomPaint(
          painter: _DashedRRectPainter(),
          child: const SizedBox(
            width: double.infinity,
            height: 56,
            child: Center(
              child: Text(
                '+ Add motorcycle',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.mutedForeground),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const LabelMono('Privacy'),
        const SizedBox(height: 8),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Default ride visibility', style: TextStyle(fontSize: 14)),
                  Text('Followers', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('Hide start & end near home', style: TextStyle(fontSize: 14)),
                  Text('On', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _col(String v, String l) {
    return Expanded(
      child: Column(
        children: [
          Text(v, style: displayStyle(size: 24)),
          const SizedBox(height: 4),
          LabelMono(l),
        ],
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final next = math.min(dist + dash, metric.length);
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
