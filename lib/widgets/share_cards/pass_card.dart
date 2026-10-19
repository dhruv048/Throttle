import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../format.dart';
import '../../models/models.dart';
import '../../theme.dart';
import '../share_card.dart';
import '../track_shape.dart';
import '../../units.dart';

/// A ticket for the ride, laid over the photo: departure and arrival with
/// the route between them, the stats, and a stub with the rider and bike.
class PassCard extends StatelessWidget {
  const PassCard({super.key, required this.item, required this.design});

  final FeedItem item;
  final ShareCardDesign design;

  static const _main = 192.0;
  static const _stub = 66.0;

  static const _paper = Color(0xFFFFFCF6);
  static const _ink = Color(0xFF1C1D21);
  static const _muted = Color(0xFF8C867B);
  static const _rule = Color(0xFFE6DFD3);

  @override
  Widget build(BuildContext context) {
    final r = item.ride;
    final units = context.units;
    final backdrop = showsPhoto(item, design) || showsMap(item, design);
    final from = item.startedLocal;
    final to = item.endedLocal;

    return Stack(
      fit: StackFit.expand,
      children: [
        ShareCardBackground(
          item: item,
          design: design,
          plain: _plain(),
          // The route goes above the ticket.
          mapPadding: const EdgeInsets.fromLTRB(28, 52, 28, 300),
        ),
        if (backdrop)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.5),
                  Colors.black.withValues(alpha: 0),
                  Colors.black.withValues(alpha: 0.25),
                ],
                stops: const [0, 0.22, 1],
              ),
            ),
          ),
        Positioned(
          top: 18,
          left: 20,
          child: ThrottleMark(
              size: 15, accent: backdrop ? AppColors.primary : _ink),
        ),
        // With no photo or map behind it, the route (or the distance) fills
        // the space above the ticket.
        if (!backdrop)
          Positioned(
            left: 28,
            right: 28,
            top: 50,
            bottom: 16 + _main + _stub + 12,
            child: item.points.length >= 2
                ? CustomPaint(
                    painter: TrackShapePainter(
                      item.points,
                      lineColor: Colors.white,
                      casingColor: Colors.white.withValues(alpha: 0.28),
                      startColor: Colors.white,
                      endColor: _ink,
                      strokeWidth: 3.6,
                      padding: 8,
                      shadow: true,
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(units.short(r.distanceKm),
                            style: displayStyle(
                                size: 88,
                                color: Colors.white,
                                weight: FontWeight.w700)),
                        const SizedBox(width: 6),
                        Text(units.distanceUnit.toUpperCase(),
                            style: displayStyle(
                                size: 26,
                                color: _ink,
                                weight: FontWeight.w700)),
                      ],
                    ),
                  ),
          ),
        if (showsMap(item, design))
          const Positioned(top: 22, right: 18, child: OsmCredit()),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          height: _main + _stub,
          child: CustomPaint(
            painter: _TicketPainter(tear: _main, paper: _paper, rule: _rule),
            child: Column(
              children: [
                SizedBox(
                  height: _main,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('RIDE PASS',
                                style: _label(color: AppColors.primary)
                                    .copyWith(fontWeight: FontWeight.w600)),
                            const Spacer(),
                            if (item.dateText != null)
                              Text(
                                  [
                                    if (item.dayText != null)
                                      item.dayText!.split(' ').first,
                                    item.dateText!,
                                  ].join(' · ').toUpperCase(),
                                  style: _label()),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.headline.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: displayStyle(size: 17, color: _ink)
                              .copyWith(letterSpacing: 0.3),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _end('Depart', from, r.startPlace ?? 'Start',
                                CrossAxisAlignment.start),
                            Expanded(child: _route()),
                            _end('Arrive', to, r.endPlace ?? 'Finish',
                                CrossAxisAlignment.end),
                          ],
                        ),
                        const Spacer(),
                        Container(height: 1, color: _rule),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _field('Distance', units.short(r.distanceKm),
                                unit: units.distanceUnit),
                            _field('Time', formatDuration(r.movingTimeSecs)),
                            _field('Avg speed',
                                '${units.speed(r.avgSpeedKmh).round()}',
                                unit: units.speedUnit),
                            _field('Top speed',
                                '${units.speed(r.maxSpeedKmh).round()}',
                                unit: units.speedUnit,
                                color: AppColors.primary),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: _stub,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                    child: Row(
                      children: [
                        _holder('Rider', item.riderText ?? 'Throttle rider'),
                        if (item.bikeText != null) ...[
                          const SizedBox(width: 12),
                          _holder('Bike', item.bikeText!),
                        ] else
                          const Spacer(),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CustomPaint(
                              size: const Size(84, 26),
                              painter: _BarcodePainter(r.id, _ink),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'THR-${_code(r.id)}',
                              style: GoogleFonts.robotoMono(
                                  fontSize: 7,
                                  letterSpacing: 1.2,
                                  color: _muted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _code(String id) {
    final clean = id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    return clean.substring(0, math.min(6, clean.length)).padLeft(6, '0');
  }

  static TextStyle _label({Color color = _muted}) =>
      labelMono(size: 8, color: color).copyWith(letterSpacing: 1.5);

  Widget _end(
      String label, DateTime? at, String place, CrossAxisAlignment align) {
    return SizedBox(
      width: 84,
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(label.toUpperCase(), style: _label()),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(at == null ? '--:--' : clockText(at),
                maxLines: 1, style: displayStyle(size: 30, color: _ink)),
          ),
          const SizedBox(height: 4),
          Text(place,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelMono(size: 9.5, color: _muted)
                  .copyWith(letterSpacing: 0.2)),
        ],
      ),
    );
  }

  /// The route between departure and arrival; a dotted line and a bike when
  /// there's no track.
  Widget _route() {
    if (item.points.length < 2) {
      return SizedBox(
        height: 58,
        child: Row(
          children: [
            Expanded(child: CustomPaint(painter: _DotsPainter(_rule))),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child:
                  Icon(Icons.two_wheeler, size: 20, color: AppColors.primary),
            ),
            Expanded(child: CustomPaint(painter: _DotsPainter(_rule))),
          ],
        ),
      );
    }
    return SizedBox(
      height: 64,
      child: CustomPaint(
        painter: TrackShapePainter(
          item.points,
          lineColor: AppColors.primary,
          casingColor: _paper,
          startColor: _ink,
          endColor: AppColors.primary,
          strokeWidth: 2.6,
          padding: 7,
        ),
      ),
    );
  }

  Widget _field(String label, String value, {String? unit, Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: _label()),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: value),
                if (unit != null)
                  TextSpan(
                      text: ' $unit',
                      style: displayStyle(size: 10.5, color: _muted)),
              ]),
              maxLines: 1,
              style: displayStyle(size: 19, color: color ?? _ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _holder(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label.toUpperCase(), style: _label()),
          const SizedBox(height: 3),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: displayStyle(size: 15, color: _ink)),
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
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Color(0xFFF39A52),
                  Color(0xFFE36B24),
                  Color(0xFFC4501C)
                ],
                stops: [0, 0.5, 1],
              ),
            ),
          ),
          CustomPaint(
              painter: TopoPainter(
                  color: Colors.white.withValues(alpha: 0.14), seed: 5)),
        ],
      );
}

/// A paper ticket: rounded, with a notch either side of a perforated tear
/// line [tear] from the top.
class _TicketPainter extends CustomPainter {
  _TicketPainter({required this.tear, required this.paper, required this.rule});

  final double tear;
  final Color paper;
  final Color rule;

  @override
  void paint(Canvas canvas, Size size) {
    const notch = 11.0;
    final outline = Path.combine(
      PathOperation.difference,
      Path()
        ..addRRect(RRect.fromRectAndRadius(
            Offset.zero & size, const Radius.circular(16))),
      Path()
        ..addOval(Rect.fromCircle(center: Offset(0, tear), radius: notch))
        ..addOval(
            Rect.fromCircle(center: Offset(size.width, tear), radius: notch)),
    );
    canvas.drawShadow(outline, Colors.black, 12, false);
    canvas.drawPath(outline, Paint()..color = paper);
    final dash = Paint()
      ..color = rule
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var x = notch + 8; x < size.width - notch - 8; x += 8) {
      canvas.drawLine(Offset(x, tear), Offset(x + 3.5, tear), dash);
    }
  }

  @override
  bool shouldRepaint(covariant _TicketPainter old) =>
      old.tear != tear || old.paper != paper;
}

/// Bars that look like a barcode, the same every time for a ride.
class _BarcodePainter extends CustomPainter {
  _BarcodePainter(this.seed, this.color);

  final String seed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final rnd = math.Random(h);
    final paint = Paint()..color = color;
    var x = 0.0;
    while (x < size.width) {
      final w = 0.8 + rnd.nextInt(3) * 0.9;
      canvas.drawRect(
          Rect.fromLTWH(x, 0, math.min(w, size.width - x), size.height), paint);
      x += w + 1 + rnd.nextInt(2) * 1.1;
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter old) => old.seed != seed;
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final paint = Paint()..color = color;
    for (var x = 2.0; x < size.width; x += 6) {
      canvas.drawCircle(Offset(x, y), 1.4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) => old.color != color;
}
