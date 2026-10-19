import 'package:flutter/material.dart';

import '../../format.dart';
import '../../models/models.dart';
import '../../theme.dart';
import '../share_card.dart';
import '../track_shape.dart';
import '../../units.dart';

/// The original card: the speeds as the big numbers with the route right
/// beside them; distance, time and bike underneath.
class ClassicCard extends StatelessWidget {
  const ClassicCard({super.key, required this.item, required this.design});

  final FeedItem item;
  final ShareCardDesign design;

  /// The route panel beside the speeds.
  static const _routeWidth = 132.0;
  static const _routeHeight = 142.0;

  @override
  Widget build(BuildContext context) {
    final r = item.ride;
    final units = context.units;
    final isMap = showsMap(item, design);
    final showTrace = !isMap && item.points.length >= 2;

    return Stack(
      fit: StackFit.expand,
      children: [
        ShareCardBackground(
          item: item,
          design: design,
          plain: _plain(),
          // The route goes where the route panel is on other cards: beside
          // the speeds, clear of the header and the stats.
          mapPadding: const EdgeInsets.fromLTRB(190, 64, 24, 112),
        ),
        // Scrims keep white text readable on any photo.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: isMap ? 0.25 : 0.45),
                Colors.transparent,
                Colors.transparent,
                Colors.black.withValues(alpha: isMap ? 0.45 : 0.5),
                Colors.black.withValues(alpha: 0.85),
              ],
              stops: const [0, 0.2, 0.3, 0.55, 1],
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: 18,
          right: 18,
          child: Row(
            children: [
              Text('THROTTLE',
                  style: displayStyle(size: 18, color: Colors.white)),
              const Spacer(),
              if (item.dateText != null)
                Text(
                  item.dateText!,
                  style: monoStyle(size: 10, tracking: 0, color: Colors.white),
                ),
            ],
          ),
        ),
        Positioned(
          left: 18,
          right: 18,
          // Clear the map's credit.
          bottom: isMap ? 30 : 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _speed(units, r.maxSpeedKmh, 'top speed'),
                        const SizedBox(height: 10),
                        _speed(units, r.avgSpeedKmh, 'avg speed'),
                      ],
                    ),
                  ),
                  if (showTrace) ...[
                    const SizedBox(width: 12),
                    _route(),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Container(height: 1, color: Colors.white.withValues(alpha: 0.25)),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _stat(
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: units.fixed(r.distanceKm, 2)),
                        TextSpan(
                          text: ' ${units.distanceUnit}',
                          style: displayStyle(
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.8)),
                        ),
                      ]),
                      style: displayStyle(size: 26, color: Colors.white),
                    ),
                    'distance',
                  ),
                  const SizedBox(width: 22),
                  _stat(
                    Text(formatDuration(r.movingTimeSecs),
                        style: displayStyle(size: 26, color: Colors.white)),
                    'time',
                  ),
                  if (item.bikeText != null) ...[
                    const SizedBox(width: 22),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Icon(Icons.two_wheeler,
                                size: 14, color: Colors.white),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                item.bikeText!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: monoStyle(
                                    size: 11, tracking: 0, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (isMap) const Positioned(right: 8, bottom: 8, child: OsmCredit()),
      ],
    );
  }

  static const _shadow = [Shadow(color: Color(0x73000000), blurRadius: 12)];

  /// A headline speed: big number, orange unit, label underneath.
  Widget _speed(Units units, double kmh, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${units.speed(kmh).round()}'),
                TextSpan(
                  text: ' ${units.speedUnit}',
                  style: displayStyle(size: 18, color: _accent)
                      .copyWith(shadows: _shadow),
                ),
              ]),
              maxLines: 1,
              style: displayStyle(size: 52, color: Colors.white)
                  .copyWith(shadows: _shadow),
            )),
        const SizedBox(height: 3),
        Text(label.toUpperCase(),
            style: labelMono(color: Colors.white.withValues(alpha: 0.8))),
      ],
    );
  }

  /// The brand orange, lifted a little so it reads on dark photos.
  static final _accent = Color.lerp(AppColors.primary, Colors.white, 0.12)!;

  /// The ride's route, drawn in a frosted panel beside the speeds.
  Widget _route() {
    return Container(
      width: _routeWidth,
      height: _routeHeight,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: CustomPaint(
        painter: TrackShapePainter(
          item.points,
          lineColor: Colors.white,
          casingColor: AppColors.primary,
          startColor: Colors.white,
          endColor: AppColors.primary,
          strokeWidth: 3,
          padding: 14,
          shadow: true,
        ),
      ),
    );
  }

  /// Distance or time. Long values (a 1,000 km tour) shrink to fit rather
  /// than push the bike off the card.
  Widget _stat(Widget value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 110),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: value,
          ),
        ),
        const SizedBox(height: 3),
        Text(label.toUpperCase(),
            style: labelMono(color: Colors.white.withValues(alpha: 0.75))),
      ],
    );
  }

  Widget _plain() => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2B2D33), Color(0xFF14151A)],
          ),
        ),
      );
}
