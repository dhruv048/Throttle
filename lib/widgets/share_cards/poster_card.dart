import 'package:flutter/material.dart';

import '../../format.dart';
import '../../models/models.dart';
import '../../theme.dart';
import '../share_card.dart';
import '../track_shape.dart';
import '../../units.dart';

/// A magazine cover: the photo full bleed, the ride's name, and the
/// distance as a number big enough to read from across the room.
class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.item, required this.design});

  final FeedItem item;
  final ShareCardDesign design;

  @override
  Widget build(BuildContext context) {
    final r = item.ride;
    final units = context.units;
    final plain = !showsPhoto(item, design) && !showsMap(item, design);
    // On the orange plain background the accents go dark.
    final accent = plain ? const Color(0xFF1B1C20) : _orange;
    final soft = Colors.white.withValues(alpha: plain ? 0.85 : 0.72);

    return Stack(
      fit: StackFit.expand,
      children: [
        ShareCardBackground(
          item: item,
          design: design,
          plain: _plain(),
          // The route fills the top of the card, above the headline.
          mapPadding: const EdgeInsets.fromLTRB(36, 60, 36, 290),
        ),
        if (!plain)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0),
                  Colors.black.withValues(alpha: 0),
                  Colors.black.withValues(alpha: 0.65),
                  Colors.black.withValues(alpha: 0.92),
                ],
                stops: const [0, 0.2, 0.36, 0.6, 1],
              ),
            ),
          ),
        // With no photo or map, the route fills the space above the text.
        if (plain && item.points.length >= 2)
          Positioned(
            left: 40,
            right: 40,
            top: 54,
            bottom: 284,
            child: CustomPaint(
              painter: TrackShapePainter(
                item.points,
                lineColor: Colors.white,
                casingColor: Colors.white.withValues(alpha: 0.28),
                startColor: Colors.white,
                endColor: accent,
                strokeWidth: 3.6,
                padding: 8,
                shadow: true,
              ),
            ),
          ),
        Positioned(
          top: 18,
          left: 20,
          right: 20,
          child: Row(
            children: [
              ThrottleMark(size: 15, accent: accent),
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
          left: 20,
          right: 20,
          bottom: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 30, height: 4, color: accent),
              const SizedBox(height: 10),
              Text(
                item.headline.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: displayStyle(size: 24, color: Colors.white)
                    .copyWith(height: 1.08, letterSpacing: 0.4),
              ),
              if (item.placesText != null) ...[
                const SizedBox(height: 5),
                Text(item.placesText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelMono(size: 11, color: soft)
                        .copyWith(letterSpacing: 0.3)),
              ],
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      units.short(r.distanceKm),
                      style: displayStyle(
                              size: 120,
                              color: Colors.white,
                              weight: FontWeight.w700)
                          .copyWith(height: 1.02, letterSpacing: -3),
                    ),
                    const SizedBox(width: 8),
                    Text(units.distanceUnit.toUpperCase(),
                        style: displayStyle(
                            size: 34, color: accent, weight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(height: 1, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  children: [
                    _stat('Time', formatDuration(r.movingTimeSecs), null, soft),
                    _divider(),
                    _stat('Avg speed', '${units.speed(r.avgSpeedKmh).round()}',
                        units.speedUnit, soft),
                    _divider(),
                    _stat('Top speed', '${units.speed(r.maxSpeedKmh).round()}',
                        units.speedUnit, soft),
                  ],
                ),
              ),
              if (item.bikeText != null || item.riderText != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (item.bikeText != null) ...[
                      Icon(Icons.two_wheeler, size: 13, color: soft),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(item.bikeText!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: labelMono(size: 10.5, color: soft)
                                .copyWith(letterSpacing: 0.4)),
                      ),
                    ],
                    const Spacer(),
                    if (item.riderText != null)
                      Text(item.riderText!,
                          style: labelMono(size: 10.5, color: soft)
                              .copyWith(letterSpacing: 0.4)),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (showsMap(item, design))
          const Positioned(right: 8, bottom: 3, child: OsmCredit()),
      ],
    );
  }

  static final _orange = Color.lerp(AppColors.primary, Colors.white, 0.1)!;

  Widget _divider() => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        color: Colors.white.withValues(alpha: 0.22),
      );

  Widget _stat(String label, String value, String? unit, Color soft) {
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
                      style: displayStyle(size: 12, color: soft)),
              ]),
              style: displayStyle(size: 24, color: Colors.white),
            ),
          ),
          const SizedBox(height: 4),
          Text(label.toUpperCase(),
              style: labelMono(size: 8.5, color: soft)
                  .copyWith(letterSpacing: 1.4)),
        ],
      ),
    );
  }

  /// Brand orange with a faint contour-line texture.
  Widget _plain() => Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF08A3E),
                  Color(0xFFE36B24),
                  Color(0xFFB9471A)
                ],
                stops: [0, 0.45, 1],
              ),
            ),
          ),
          CustomPaint(
              painter: TopoPainter(
                  color: Colors.white.withValues(alpha: 0.12), seed: 3)),
        ],
      );
}
