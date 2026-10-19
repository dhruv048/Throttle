import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../models/models.dart';
import '../theme.dart';
import 'map_tiles.dart';
import 'profile_tabs.dart' show FlagCard, FlagsMapScreen, openFlagRide;
import 'ride_flag.dart';
import 'skeleton.dart';
import 'ui.dart';
import '../units.dart';

/// The rider's flags, as a moment: the Earth turns to where they ride, then
/// the view drops down into the map, where each flag is planted. Then it's
/// a map to explore: tap a flag for its ride.
class FlagsGlobe extends ConsumerStatefulWidget {
  const FlagsGlobe({super.key, required this.flags, this.height = 440});

  /// Null while they load.
  final List<RideFlag>? flags;
  final double height;

  @override
  ConsumerState<FlagsGlobe> createState() => _FlagsGlobeState();
}

class _FlagsGlobeState extends ConsumerState<FlagsGlobe>
    with TickerProviderStateMixin {
  /// A clear sky, behind the Earth.
  static const _sky = [Color(0xFFD7E8F4), Color(0xFFEFF4F7), Color(0xFFF7F5F1)];

  /// From space down to the flags, once.
  late final AnimationController _intro = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3800));

  /// The Earth turning slowly while there's nothing to fly to.
  late final AnimationController _idle =
      AnimationController(vsync: this, duration: const Duration(seconds: 60));

  final _map = MapController();
  bool _mapReady = false;

  /// Where the camera ends up, once the map has a size to fit the flags in.
  MapCamera? _target;

  /// The world's map, and the shader that wraps it round the globe. Null
  /// until loaded (or if they can't be): a plain painted globe meanwhile.
  ui.Image? _world;
  ui.FragmentShader? _shader;
  RideFlag? _selected;
  bool _opening = false;

  /// The map comes in at this zoom, then flies to [_target].
  static const _arrivalZoom = 3.2;

  List<RideFlag> get _flags => widget.flags ?? const [];

  LatLng get _centre {
    final flags = _flags;
    if (flags.isEmpty) return const LatLng(20, 80);
    var lat = 0.0, lng = 0.0;
    for (final f in flags) {
      lat += f.lat;
      lng += f.lng;
    }
    return LatLng(lat / flags.length, lng / flags.length);
  }

  bool get _reducedMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    WorldPicture.load().then((world) {
      if (mounted) setState(() => _world = world);
    }, onError: (_) {});
    WorldPicture.shader().then((shader) {
      if (mounted) setState(() => _shader = shader);
    }, onError: (_) {});
    _intro.addListener(_fly);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _start();
  }

  @override
  void didUpdateWidget(covariant FlagsGlobe old) {
    super.didUpdateWidget(old);
    if (old.flags?.length != widget.flags?.length) {
      _target = null;
      _start();
      if (_intro.isCompleted) _fitWhenReady();
    }
  }

  /// Flies in once the flags are known; turns slowly till then (or if
  /// there are none).
  void _start() {
    final flags = widget.flags;
    if (flags == null || flags.isEmpty) {
      if (!_idle.isAnimating && !_reducedMotion) _idle.repeat();
      return;
    }
    if (_intro.isAnimating || _intro.isCompleted) return;
    _idle.stop();
    if (_reducedMotion) {
      _intro.value = 1;
    } else {
      _intro.forward();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _idle.dispose();
    _map.dispose();
    _shader?.dispose();
    super.dispose();
  }

  void _onMapReady() {
    _mapReady = true;
    _fitWhenReady();
  }

  /// The camera that fits every flag, clear of the count.
  void _fitWhenReady() {
    if (!_mapReady || _flags.isEmpty) return;
    final points = [for (final f in _flags) LatLng(f.lat, f.lng)];
    _target = CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.fromLTRB(40, 130, 40, 56),
      maxZoom: 12,
    ).fit(_map.camera);
    _fly();
  }

  /// Moves the map along the flight: from [_arrivalZoom] over the middle of
  /// the flags down to [_target].
  void _fly() {
    final target = _target;
    if (!_mapReady || target == null) return;
    final t = Curves.easeInOutCubic
        .transform(((_intro.value - 0.5) / 0.45).clamp(0.0, 1.0));
    final from = _centre;
    final zoom = _arrivalZoom + (target.zoom - _arrivalZoom) * t;
    final centre = LatLng(
      from.latitude + (target.center.latitude - from.latitude) * t,
      from.longitude + (target.center.longitude - from.longitude) * t,
    );
    _map.move(centre, zoom);
  }

  /// Skips to the end of the flight.
  void _skip() {
    if (_intro.isAnimating) _intro.value = 1;
  }

  Future<void> _open(RideFlag flag) async {
    setState(() => _opening = true);
    await openFlagRide(context, ref, flag);
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final flags = _flags;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: widget.height,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _sky,
            ),
          ),
          child: AnimatedBuilder(
            animation: Listenable.merge([_intro, _idle]),
            builder: (context, _) {
              final t = _intro.value;
              final mapIn = ((t - 0.5) / 0.12).clamp(0.0, 1.0);
              final flying = _intro.isAnimating;
              return Stack(
                children: [
                  if (flags.isNotEmpty)
                    Positioned.fill(
                      child: Opacity(
                        opacity: mapIn,
                        child: IgnorePointer(
                          ignoring: flying || mapIn < 1,
                          child: _mapView(flags),
                        ),
                      ),
                    ),
                  if (mapIn < 1)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _skip,
                        child: CustomPaint(painter: _globe(t)),
                      ),
                    ),
                  Positioned(
                    left: 12,
                    top: 12,
                    right: 70,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: IgnorePointer(child: _countPanel(flags, t)),
                    ),
                  ),
                  if (flags.isNotEmpty && !flying)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Material(
                        color: Colors.white,
                        elevation: 2,
                        shadowColor: Colors.black26,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Full screen',
                          icon: const Icon(Icons.open_in_full,
                              size: 18, color: AppColors.foreground),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => FlagsMapScreen(flags: flags)),
                          ),
                        ),
                      ),
                    ),
                  if (widget.flags != null && flags.isEmpty)
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 20,
                      child: Text(
                        'Every ride plants a flag at the furthest point you '
                        'reach. Your first one is waiting.',
                        style: const TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: AppColors.mutedForeground),
                      ),
                    ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 16,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _selected == null
                          ? const SizedBox.shrink()
                          : FlagCard(
                              key: ValueKey(_selected!.rideId),
                              flag: _selected!,
                              opening: _opening,
                              onOpen: () => _open(_selected!),
                            ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  _GlobePainter _globe(double t) {
    final centre = _centre;
    // Turns to the flags, then dives in, down to the map's own scale.
    final turn = Curves.easeInOutCubic.transform((t / 0.44).clamp(0.0, 1.0));
    final dive = Curves.easeInCubic.transform(((t - 0.4) / 0.22).clamp(0.0, 1));
    final idle = _idle.value * 360;
    final hasFlags = _flags.isNotEmpty;
    return _GlobePainter(
      world: _world,
      shader: _shader,
      flags: [for (final f in _flags) LatLng(f.lat, f.lng)],
      lng0: hasFlags
          ? centre.longitude - 150 * (1 - turn)
          : centre.longitude + idle,
      lat0: hasFlags ? 12 + (centre.latitude.clamp(-55, 55) - 12) * turn : 12,
      dive: dive,
      // How big the Earth is on the map it hands over to (Web Mercator
      // stretches by 1 / cos(latitude)).
      arrivalRadius: 256 *
          math.pow(2, _arrivalZoom) /
          (2 * math.pi) /
          math.cos(centre.latitude.clamp(-80, 80) * math.pi / 180),
      opacity: 1 - ((t - 0.52) / 0.1).clamp(0.0, 1.0),
      glow: (math.sin(_idle.value * 2 * math.pi * 30) + 1) / 2,
    );
  }

  Widget _mapView(List<RideFlag> flags) {
    final selected = _selected;
    final planted = ((_intro.value - 0.86) / 0.14).clamp(0.0, 1.0);
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _centre,
        initialZoom: _arrivalZoom,
        backgroundColor: AppColors.panel,
        onMapReady: _onMapReady,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom |
              InteractiveFlag.pinchMove |
              InteractiveFlag.doubleTapZoom |
              InteractiveFlag.scrollWheelZoom,
        ),
        onTap: (_, __) => setState(() => _selected = null),
      ),
      children: [
        MapTiles.layer(),
        MarkerLayer(
          markers: [
            for (var i = 0; i < flags.length; i++)
              if (flags[i] != selected)
                _planted(flags[i], i, planted, flags.length),
            if (selected != null)
              flagMarker((lat: selected.lat, lng: selected.lng),
                  key: ValueKey(selected.rideId), selected: true),
          ],
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            color: Colors.white.withValues(alpha: 0.75),
            child: const Text('© OpenStreetMap',
                style: TextStyle(fontSize: 9, color: Color(0xFF555555))),
          ),
        ),
      ],
    );
  }

  /// A flag going in, one after another as the camera lands.
  Marker _planted(RideFlag f, int i, double planted, int count) {
    final stagger = count <= 1 ? 0.0 : i / count * 0.5;
    final t = ((planted - stagger) / 0.5).clamp(0.0, 1.0);
    final marker = flagMarker((lat: f.lat, lng: f.lng),
        key: ValueKey(f.rideId), onTap: () => setState(() => _selected = f));
    return Marker(
      key: marker.key,
      point: marker.point,
      width: marker.width,
      height: marker.height,
      alignment: marker.alignment,
      child: Transform.scale(
        scale: Curves.easeOutBack.transform(t),
        alignment: Alignment.bottomLeft,
        child: Opacity(opacity: t, child: marker.child),
      ),
    );
  }

  /// [_count] on a frosted panel, so it reads over the globe and the map.
  Widget _countPanel(List<RideFlag> flags, double t) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 3)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 16, 12),
          child: _count(flags, t),
        ),
      );

  /// "12 FLAGS PLANTED · 7 places · 1,234 km", counting up as it flies.
  Widget _count(List<RideFlag> flags, double t) {
    if (widget.flags == null) {
      return const Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 70, height: 48),
            SizedBox(height: 8),
            SkeletonBox(width: 140, height: 11),
          ],
        ),
      );
    }
    final grow = flags.isEmpty
        ? 1.0
        : Curves.easeOutCubic.transform(((t - 0.1) / 0.5).clamp(0.0, 1.0));
    final places = {
      for (final f in flags)
        if (f.place != null) f.place!,
    }.length;
    final km = flags.fold<double>(0, (sum, f) => sum + f.distanceKm);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${(flags.length * grow).round()}', style: displayStyle(size: 56)),
        const SizedBox(height: 4),
        LabelMono(flags.length == 1 ? 'Flag planted' : 'Flags planted',
            color: AppColors.primary),
        if (flags.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            [
              if (places > 0) '$places ${places == 1 ? 'place' : 'places'}',
              '${context.units.totalText(km * grow)} ridden',
            ].join(' · '),
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedForeground),
          ),
        ],
      ],
    );
  }
}

/// The Earth from space (orthographic), lit, wrapped in the world's map
/// ([shader] with [world]); a plain painted globe until those load. The
/// rider's flags glow on it.
class _GlobePainter extends CustomPainter {
  _GlobePainter({
    required this.world,
    required this.shader,
    required this.flags,
    required this.lng0,
    required this.lat0,
    required this.dive,
    required this.arrivalRadius,
    required this.opacity,
    required this.glow,
  });

  final ui.Image? world;
  final ui.FragmentShader? shader;
  final List<LatLng> flags;

  /// The point facing the viewer.
  final double lng0;
  final double lat0;

  /// 0 → 1: from the whole Earth down to [arrivalRadius].
  final double dive;
  final double arrivalRadius;
  final double opacity;

  /// 0 → 1: how bright the flags glow.
  final double glow;

  static const _rad = math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final r0 = math.min(size.width * 0.4, size.height * 0.34);
    // Zooms at an even pace (in scale), and settles in the middle, where
    // the map puts the flags.
    final r = math.exp(ui.lerpDouble(
        math.log(r0), math.log(math.max(arrivalRadius, r0)), dive)!);
    final c =
        Offset(size.width / 2, size.height * ui.lerpDouble(0.6, 0.5, dive)!);
    final sinLat0 = math.sin(lat0 * _rad), cosLat0 = math.cos(lat0 * _rad);

    // (x, y, facing): facing > 0 on the near side.
    (double, double, double) project(double lat, double lng) {
      final phi = lat * _rad, dl = (lng - lng0) * _rad;
      final cosPhi = math.cos(phi), sinPhi = math.sin(phi);
      final facing = sinLat0 * sinPhi + cosLat0 * cosPhi * math.cos(dl);
      return (
        c.dx + r * cosPhi * math.sin(dl),
        c.dy - r * (cosLat0 * sinPhi - sinLat0 * cosPhi * math.cos(dl)),
        facing,
      );
    }

    final world = this.world;
    final shader = this.shader;
    if (world != null && shader != null) {
      shader
        ..setFloat(0, c.dx)
        ..setFloat(1, c.dy)
        ..setFloat(2, r)
        ..setFloat(3, lng0 * _rad)
        ..setFloat(4, lat0 * _rad)
        ..setFloat(5, opacity)
        ..setImageSampler(0, world, filterQuality: FilterQuality.medium);
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    } else {
      _plain(canvas, size, c, r, project);
    }

    // The rider's flags.
    for (final f in flags) {
      final (x, y, facing) = project(f.latitude, f.longitude);
      if (facing <= 0) continue;
      final p = Offset(x, y);
      canvas.drawCircle(
          p,
          7 + 5 * glow,
          Paint()
            ..color = AppColors.primary
                .withValues(alpha: (0.22 + 0.22 * glow) * opacity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawCircle(p, 3.6,
          Paint()..color = AppColors.primary.withValues(alpha: opacity));
      canvas.drawCircle(
          p,
          3.6,
          Paint()
            ..color = Colors.white.withValues(alpha: opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
    }
  }

  /// Ocean blue with lines of latitude and longitude, for while the world's
  /// map loads (or if it can't).
  void _plain(Canvas canvas, Size size, Offset c, double r,
      (double, double, double) Function(double, double) project) {
    canvas.saveLayer(Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: opacity));
    canvas.drawCircle(
      c,
      r * 1.18,
      Paint()
        ..shader = ui.Gradient.radial(c, r * 1.18, [
          const Color(0xFFB3D6EE).withValues(alpha: 0.7),
          const Color(0x00B3D6EE),
        ], [
          0.84,
          1
        ]),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c + Offset(-r * 0.35, -r * 0.4),
          r * 1.5,
          const [Color(0xFFCFE6F4), Color(0xFF9CC8E2), Color(0xFF7DAFCD)],
          const [0, 0.6, 1],
        ),
    );
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    void line(Iterable<(double, double)> points) {
      final path = Path();
      var drawing = false;
      for (final (lat, lng) in points) {
        final (x, y, facing) = project(lat, lng);
        if (facing <= 0) {
          drawing = false;
          continue;
        }
        drawing ? path.lineTo(x, y) : path.moveTo(x, y);
        drawing = true;
      }
      canvas.drawPath(path, grid);
    }

    for (var lng = -180.0; lng < 180; lng += 30) {
      line([for (var lat = -90.0; lat <= 90; lat += 4) (lat, lng)]);
    }
    for (var lat = -60.0; lat <= 60; lat += 30) {
      line([for (var lng = -180.0; lng <= 180; lng += 4) (lat, lng)]);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlobePainter old) =>
      old.world != world ||
      old.shader != shader ||
      old.flags != flags ||
      old.lng0 != lng0 ||
      old.lat0 != lat0 ||
      old.dive != dive ||
      old.arrivalRadius != arrivalRadius ||
      old.opacity != opacity ||
      old.glow != glow;
}

/// The world's map as one picture (the 16 tiles of zoom level 2, 1024 px
/// square, Web Mercator), and the shader that wraps it round a globe.
/// Each loads once; a failed load is tried again next time.
class WorldPicture {
  WorldPicture._();

  static const _zoom = 2;
  static const _tile = 256;

  static Future<ui.Image>? _loading;
  static Future<ui.FragmentProgram>? _program;

  static Future<ui.Image> load() => _loading ??= _load().catchError(
        (Object e) {
          _loading = null;
          throw e;
        },
      );

  static Future<ui.FragmentShader> shader() async {
    _program ??= ui.FragmentProgram.fromAsset('shaders/globe.frag')
        .catchError((Object e) {
      _program = null;
      throw e;
    });
    return (await _program!).fragmentShader();
  }

  static Future<ui.Image> _load() async {
    const n = 1 << _zoom;
    final tiles = await Future.wait([
      for (var y = 0; y < n; y++)
        for (var x = 0; x < n; x++) _resolve(MapTiles.tileImage(_zoom, x, y)),
    ]);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (var i = 0; i < tiles.length; i++) {
      final tile = tiles[i];
      canvas.drawImageRect(
        tile,
        Rect.fromLTWH(0, 0, tile.width.toDouble(), tile.height.toDouble()),
        Rect.fromLTWH(((i % n) * _tile).toDouble(),
            ((i ~/ n) * _tile).toDouble(), _tile.toDouble(), _tile.toDouble()),
        paint,
      );
      tile.dispose();
    }
    return recorder.endRecording().toImage(n * _tile, n * _tile);
  }

  static Future<ui.Image> _resolve(ImageProvider provider) {
    final done = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (!done.isCompleted) done.complete(info.image.clone());
      info.dispose();
      stream.removeListener(listener);
    }, onError: (error, stack) {
      if (!done.isCompleted) done.completeError(error, stack);
      stream.removeListener(listener);
    });
    stream.addListener(listener);
    return done.future;
  }
}
