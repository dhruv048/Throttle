import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;

import '../models/models.dart';
import '../theme.dart';
import 'share_cards/classic_card.dart';
import 'share_cards/cockpit_card.dart';
import 'share_cards/pass_card.dart';
import 'share_cards/poster_card.dart';
import 'share_cards/trace_card.dart';
import 'skeleton.dart';
import 'tracked_route_map.dart';

/// What's behind the stats on a ride card.
enum ShareBackground { bike, photo, map, plain }

/// How a ride card is laid out.
enum ShareCardStyle {
  /// A magazine cover: the photo, the ride's name and a huge distance.
  poster('Poster'),

  /// A motorcycle's dash: top speed on a speedometer, distance on an
  /// odometer.
  cockpit('Cockpit'),

  /// A ticket for the ride: departure and arrival, the route between them.
  pass('Ride pass'),

  /// The route as the hero, glowing and coloured by speed.
  trace('Trace'),

  /// The original card: speeds and route over the background.
  classic('Original');

  const ShareCardStyle(this.label);

  final String label;
}

/// The rider's choices for a ride card.
@immutable
class ShareCardDesign {
  const ShareCardDesign(this.background,
      {this.photo, this.style = ShareCardStyle.poster});

  /// The bike's photo if it has one, else the route map, else plain.
  factory ShareCardDesign.initial(FeedItem item) => ShareCardDesign(
        item.bikePhotoUrl != null
            ? ShareBackground.bike
            : item.points.length >= 2
                ? ShareBackground.map
                : ShareBackground.plain,
      );

  final ShareBackground background;
  final ShareCardStyle style;

  /// The rider's own photo. Kept while another background is picked, so
  /// switching back doesn't lose it.
  final Uint8List? photo;

  ShareCardDesign withBackground(ShareBackground background) =>
      ShareCardDesign(background, photo: photo, style: style);

  ShareCardDesign withStyle(ShareCardStyle style) =>
      ShareCardDesign(background, photo: photo, style: style);

  /// The rider's own photo, as the background.
  ShareCardDesign withPhoto(Uint8List photo) =>
      ShareCardDesign(ShareBackground.photo, photo: photo, style: style);
}

/// The ride card, in the design's style. Laid out at [size] logical pixels
/// and rendered at [pixelRatio], i.e. a 1080×1350 (4:5) image.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.item, required this.design});

  static const size = Size(360, 450);
  static const pixelRatio = 3.0;

  final FeedItem item;
  final ShareCardDesign design;

  @override
  Widget build(BuildContext context) {
    // Its own Material, so its text looks the same wherever it's rendered.
    return Material(
      type: MaterialType.transparency,
      child: switch (design.style) {
        ShareCardStyle.poster => PosterCard(item: item, design: design),
        ShareCardStyle.cockpit => CockpitCard(item: item, design: design),
        ShareCardStyle.pass => PassCard(item: item, design: design),
        ShareCardStyle.trace => TraceCard(item: item, design: design),
        ShareCardStyle.classic => ClassicCard(item: item, design: design),
      },
    );
  }
}

/// What every card style draws on: the bike photo, the rider's photo, the
/// route map, or [plain] (also the fallback when a photo can't be shown).
class ShareCardBackground extends StatelessWidget {
  const ShareCardBackground({
    super.key,
    required this.item,
    required this.design,
    required this.plain,
    required this.mapPadding,
    this.darkMap = false,
  });

  final FeedItem item;
  final ShareCardDesign design;
  final Widget plain;

  /// Where on the card the route goes on the map background: clear of the
  /// style's text.
  final EdgeInsets mapPadding;

  /// The map in night colours.
  final bool darkMap;

  @override
  Widget build(BuildContext context) {
    switch (design.background) {
      case ShareBackground.bike:
        final url = item.bikePhotoUrl;
        return url == null ? plain : NetworkPhoto(url, fallback: plain);
      case ShareBackground.photo:
        final photo = design.photo;
        return photo == null
            ? plain
            : Image.memory(photo, fit: BoxFit.cover, gaplessPlayback: true);
      case ShareBackground.map:
        if (item.points.length < 2) return plain;
        return IgnorePointer(
          child: TrackedRouteMap.track(
            item.points,
            height: ShareCard.size.height,
            interactive: false,
            fitPadding: mapPadding,
            // Each style places the credit itself ([OsmCredit]), clear of
            // its text.
            attribution: false,
            dark: darkMap,
          ),
        );
      case ShareBackground.plain:
        return plain;
    }
  }
}

/// Whether [design] shows the route map behind the card.
bool showsMap(FeedItem item, ShareCardDesign design) =>
    design.background == ShareBackground.map && item.points.length >= 2;

/// Whether [design] shows a photo behind the card.
bool showsPhoto(FeedItem item, ShareCardDesign design) =>
    switch (design.background) {
      ShareBackground.bike => item.bikePhotoUrl != null,
      ShareBackground.photo => design.photo != null,
      _ => false,
    };

/// The OpenStreetMap credit the map tiles' licence requires.
class OsmCredit extends StatelessWidget {
  const OsmCredit({super.key, this.color = const Color(0xB3FFFFFF)});

  final Color color;

  @override
  Widget build(BuildContext context) => Text(
        '© OpenStreetMap contributors',
        style: labelMono(size: 7, color: color).copyWith(letterSpacing: 0.2),
      );
}

/// The Throttle wordmark: three rising bars and the name.
class ThrottleMark extends StatelessWidget {
  const ThrottleMark({
    super.key,
    this.size = 16,
    this.color = Colors.white,
    this.accent = AppColors.primary,
  });

  final double size;
  final Color color;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size(size * 0.95, size * 0.8),
          painter: _BarsPainter(accent),
        ),
        SizedBox(width: size * 0.35),
        Text(
          'THROTTLE',
          style: displayStyle(size: size, color: color)
              .copyWith(letterSpacing: size * 0.08),
        ),
      ],
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / 4;
    final lean = size.height * 0.28;
    final paint = Paint()..color = color;
    for (var i = 0; i < 3; i++) {
      final h = size.height * (0.5 + i * 0.25);
      final x = i * w * 1.35;
      canvas.drawPath(
        Path()
          ..moveTo(x + lean * h / size.height, size.height - h)
          ..lineTo(x + w + lean * h / size.height, size.height - h)
          ..lineTo(x + w, size.height)
          ..lineTo(x, size.height)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => old.color != color;
}

/// Slow to fast, for anything coloured by speed.
const heatColors = [Color(0xFFFFD36E), Color(0xFFFF8A3D), Color(0xFFFF3B5C)];

/// The [heatColors] colour [f] (0 = slow, 1 = fast) of the way along.
Color heatColor(double f) {
  final t = f.clamp(0.0, 1.0);
  return t < 0.5
      ? Color.lerp(heatColors[0], heatColors[1], t * 2)!
      : Color.lerp(heatColors[1], heatColors[2], (t - 0.5) * 2)!;
}

/// Topographic contour lines: a quiet texture for plain backgrounds.
class TopoPainter extends CustomPainter {
  TopoPainter({required this.color, this.seed = 7});

  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final peaks = [
      Offset(size.width * 0.82, size.height * 0.18),
      Offset(size.width * 0.12, size.height * 0.62),
      Offset(size.width * 0.7, size.height * 0.95),
    ];
    for (final peak in peaks) {
      final phase = rnd.nextDouble() * math.pi * 2;
      final lobes = 2 + rnd.nextInt(3);
      for (var ring = 1; ring <= 16; ring++) {
        final r = ring * 17.0;
        final path = Path();
        for (var i = 0; i <= 90; i++) {
          final a = i / 90 * math.pi * 2;
          final wobble = 1 +
              0.18 * math.sin(a * lobes + phase + ring * 0.25) +
              0.07 * math.sin(a * 5 - phase);
          final p = peak + Offset(math.cos(a), math.sin(a)) * r * wobble;
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant TopoPainter old) =>
      old.color != color || old.seed != seed;
}

/// Ride details as the cards print them.
extension ShareText on FeedItem {
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
    'Friday', 'Saturday', 'Sunday',
  ];

  DateTime? get startedLocal => ride.rodeAt?.toLocal();

  /// When the ride ended: as recorded, else its start plus its moving time.
  DateTime? get endedLocal =>
      ride.endedAt?.toLocal() ??
      ride.startedAt?.toLocal().add(Duration(seconds: ride.movingTimeSecs));

  /// "9 Oct 2026".
  String? get dateText {
    final t = startedLocal;
    return t == null ? null : '${t.day} ${_months[t.month - 1]} ${t.year}';
  }

  /// "Sat 9 Oct".
  String? get dayText {
    final t = startedLocal;
    return t == null
        ? null
        : '${_days[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}';
  }

  /// The rider's own title for the ride, or else when it was: "Saturday
  /// morning ride". The app's default title ("Ride · 42.4 km") only repeats
  /// the distance, so it's never the headline.
  String get headline {
    final title = ride.title.trim();
    if (title.isNotEmpty && title != 'Ride' && !title.startsWith('Ride · ')) {
      return title;
    }
    final t = startedLocal;
    if (t == null) return 'Ride';
    final part = switch (t.hour) {
      >= 5 && < 12 => 'morning',
      >= 12 && < 17 => 'afternoon',
      >= 17 && < 21 => 'evening',
      _ => 'night',
    };
    return '${_dayNames[t.weekday - 1]} $part ride';
  }

  /// "Bhaktapur → Nagarkot", when both ends are known.
  String? get placesText => ride.startPlace != null && ride.endPlace != null
      ? '${ride.startPlace} → ${ride.endPlace}'
      : null;

  /// "@dhruv", else the rider's name.
  String? get riderText {
    final username = rider.username;
    if (username != null && username.isNotEmpty) return '@$username';
    final name = rider.displayName;
    return name == null || name.trim().isEmpty ? null : name.trim();
  }

  String? get bikeText =>
      bikeName == null || bikeName!.trim().isEmpty ? null : bikeName!.trim();
}

/// "06:05".
String clockText(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// A [ShareCard] laid out at its full size and scaled to fit whatever space
/// it's given, inside a boundary that [renderShareCard] can capture.
class ShareCardFrame extends StatelessWidget {
  const ShareCardFrame({
    super.key,
    required this.boundaryKey,
    required this.item,
    required this.design,
  });

  final GlobalKey boundaryKey;
  final FeedItem item;
  final ShareCardDesign design;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      child: RepaintBoundary(
        key: boundaryKey,
        child: SizedBox.fromSize(
          size: ShareCard.size,
          child: ClipRect(child: ShareCard(item: item, design: design)),
        ),
      ),
    );
  }
}

/// Renders the [ShareCardFrame] behind [boundaryKey] as a 1080×1350 image.
/// Waits for a background photo and the card's fonts to finish loading
/// first, so the image never captures a placeholder.
Future<ui.Image> renderShareCard(
  BuildContext context,
  GlobalKey boundaryKey, {
  required FeedItem item,
  required ShareCardDesign design,
}) async {
  final ImageProvider? photo = switch (design.background) {
    ShareBackground.bike when item.bikePhotoUrl != null =>
      NetworkImage(item.bikePhotoUrl!),
    ShareBackground.photo when design.photo != null =>
      MemoryImage(design.photo!),
    _ => null,
  };
  if (photo != null) {
    // A photo that can't load falls back to the plain background.
    await precacheImage(photo, context, onError: (_, __) {})
        .timeout(const Duration(seconds: 10), onTimeout: () {});
  }
  // Fonts that couldn't be fetched draw in the fallback font.
  await GoogleFonts.pendingFonts()
      .then((_) {}, onError: (_) {})
      .timeout(const Duration(seconds: 10), onTimeout: () {});
  await WidgetsBinding.instance.endOfFrame;
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return boundary.toImage(pixelRatio: ShareCard.pixelRatio);
}

/// A ride card as a JPEG, made without it being on screen: laid out off to
/// the side in the app's root overlay (above every page, so nothing covers
/// it) just long enough to capture.
Future<Uint8List> renderShareCardJpeg(
  BuildContext context, {
  required FeedItem item,
  required ShareCardDesign design,
}) async {
  final key = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -4 * ShareCard.size.width,
      top: 0,
      width: ShareCard.size.width,
      height: ShareCard.size.height,
      child: IgnorePointer(
        child: ShareCardFrame(boundaryKey: key, item: item, design: design),
      ),
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) throw StateError('Ride card no longer needed');
    final image =
        await renderShareCard(context, key, item: item, design: design);
    try {
      return await encodeJpeg(image);
    } finally {
      image.dispose();
    }
  } finally {
    entry.remove();
  }
}

/// PNG for sharing to other apps (lossless; size doesn't matter there).
Future<Uint8List> encodePng(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw StateError('Could not render image');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// JPEG for uploading: a tenth of the PNG's size for a photo background,
/// which everyone who opens the ride downloads. Encoded off the UI thread.
Future<Uint8List> encodeJpeg(ui.Image image, {int quality = 85}) async {
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (rgba == null) throw StateError('Could not render image');
  return compute(
    _encodeJpeg,
    (
      rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
      image.width,
      image.height,
      quality,
    ),
  );
}

Uint8List _encodeJpeg((Uint8List, int, int, int) args) {
  final (rgba, width, height, quality) = args;
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: quality, chroma: img.JpegChroma.yuv420);
}
