import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../theme.dart';
import 'map_tiles.dart';

/// Full-screen map for an in-progress ride: follows the rider, draws the
/// track as it grows, and shows the current fix with its accuracy circle.
///
/// GPS fixes arrive about once a second. Rather than jumping to each one,
/// the dot (and the camera, while following) glides from where it is to the
/// new fix over roughly the time until the next one is due, so it moves
/// continuously like a navigation app. While [recording], the end of the
/// trail is drawn up to the gliding dot, so the line grows with it.
///
/// [topInset]/[bottomInset] are the heights covered by overlays, so the
/// rider's dot is kept in the middle of the part of the map you can see.
class LiveRideMap extends StatefulWidget {
  const LiveRideMap({
    super.key,
    required this.trail,
    this.here,
    this.accuracyM,
    this.recording = true,
    this.topInset = 0,
    this.bottomInset = 0,
  });

  final List<LatLng> trail;
  final LatLng? here;
  final double? accuracyM;

  /// Whether the trail is growing (false while paused: the dot still moves,
  /// the line doesn't follow it).
  final bool recording;
  final double topInset;
  final double bottomInset;

  @override
  State<LiveRideMap> createState() => _LiveRideMapState();
}

class _LiveRideMapState extends State<LiveRideMap>
    with SingleTickerProviderStateMixin {
  static const _zoom = 16.5;
  // Used only until the first fix arrives.
  static const _fallbackCenter = LatLng(27.7172, 85.3240);
  static const _dotColor = Color(0xFF2F80ED);

  /// Bounds on how long one glide takes. It's normally the time since the
  /// previous fix, so the dot arrives about when the next fix does.
  static const _minGlide = Duration(milliseconds: 300);
  static const _maxGlide = Duration(milliseconds: 1500);

  /// A fix further than this from the dot is jumped to, not glided to (the
  /// first good fix after a GPS glitch, or after the app was away).
  static const _snapM = 150.0;

  /// Movement smaller than this doesn't change the heading, so a stopped
  /// rider's arrow doesn't spin with GPS wander.
  static const _headingMinM = 3.0;

  static const _distance = Distance();

  final _map = MapController();
  late final _glide = AnimationController(vsync: this)..addListener(_onGlide);
  bool _ready = false;
  bool _follow = true;

  // The glide in progress: from the dot's position to the latest fix.
  LatLng? _from;
  LatLng? _to;
  double? _fromAccuracy;
  double? _toAccuracy;
  double? _fromHeading;
  double? _toHeading;
  DateTime? _lastFixAt;

  // What's on screen this frame.
  LatLng? _shown;
  double? _shownAccuracy;

  /// Degrees clockwise from north; null until the rider has moved.
  double? _shownHeading;

  /// The committed trail, cached so it isn't re-projected every frame.
  late Widget _trailLayer;
  List<LatLng> _trailBody = const [];

  Offset get _centerOffset =>
      Offset(0, (widget.topInset - widget.bottomInset) / 2);

  @override
  void initState() {
    super.initState();
    _shown = _to = widget.here;
    _shownAccuracy = _toAccuracy = widget.accuracyM;
    if (widget.here != null) _lastFixAt = DateTime.now();
    _buildTrailLayer();
  }

  @override
  void didUpdateWidget(covariant LiveRideMap old) {
    super.didUpdateWidget(old);
    final here = widget.here;
    if (here != old.here) _onFix(here);
    // A new fix moves where the committed trail ends (see _buildTrailLayer).
    if (here != old.here ||
        !identical(widget.trail, old.trail) ||
        widget.recording != old.recording) {
      _buildTrailLayer();
    }
  }

  void _onFix(LatLng? here) {
    final now = DateTime.now();
    final since = _lastFixAt == null ? _maxGlide : now.difference(_lastFixAt!);
    _lastFixAt = now;

    final shown = _shown;
    if (here == null) {
      _glide.stop();
      _shown = _from = _to = null;
      return;
    }

    final prev = _to;
    if (prev != null && _distance(prev, here) >= _headingMinM) {
      _toHeading = _distance.bearing(prev, here);
    }
    if (shown == null || _distance(shown, here) > _snapM) {
      _glide.stop();
      _shown = _from = _to = here;
      _shownAccuracy = _fromAccuracy = _toAccuracy = widget.accuracyM;
      _shownHeading = _fromHeading = _toHeading;
      _moveCamera();
      return;
    }

    _from = shown;
    _to = here;
    _fromAccuracy = _shownAccuracy ?? widget.accuracyM;
    _toAccuracy = widget.accuracyM;
    _fromHeading = _shownHeading ?? _toHeading;
    _glide.duration = Duration(
      microseconds: since.inMicroseconds
          .clamp(_minGlide.inMicroseconds, _maxGlide.inMicroseconds),
    );
    _glide.forward(from: 0);
  }

  void _onGlide() {
    final from = _from, to = _to;
    if (from == null || to == null) return;
    final t = _glide.value;
    setState(() {
      _shown = LatLng(
        from.latitude + (to.latitude - from.latitude) * t,
        from.longitude + (to.longitude - from.longitude) * t,
      );
      final a0 = _fromAccuracy, a1 = _toAccuracy;
      _shownAccuracy = a0 == null || a1 == null ? a1 : a0 + (a1 - a0) * t;
      final h0 = _fromHeading, h1 = _toHeading;
      if (h0 != null && h1 != null) {
        // The short way round: 350° → 10° turns through north.
        final turn = (h1 - h0 + 540) % 360 - 180;
        _shownHeading = h0 + turn * t;
      } else {
        _shownHeading = h1;
      }
    });
    _moveCamera();
  }

  void _moveCamera() {
    final shown = _shown;
    if (_ready && _follow && shown != null) {
      _map.move(shown, _map.camera.zoom, offset: _centerOffset);
    }
  }

  /// The trail up to the latest fix. While recording, a point at the fix
  /// the dot is still gliding to is left to the tail ([_tail]), or the line
  /// would run ahead of the dot.
  void _buildTrailLayer() {
    final trail = widget.trail;
    _trailBody = widget.recording && trail.isNotEmpty && trail.last == _to
        ? trail.sublist(0, trail.length - 1)
        : trail;
    _trailLayer = _trailBody.length > 1
        ? PolylineLayer(polylines: [_line(_trailBody)])
        : const SizedBox.shrink();
  }

  /// From the end of the committed trail to the dot.
  List<LatLng>? get _tail {
    final shown = _shown;
    if (!widget.recording || shown == null || _trailBody.isEmpty) return null;
    return [_trailBody.last, shown];
  }

  static Polyline _line(List<LatLng> points, {bool border = true}) => Polyline(
        points: points,
        color: AppColors.primary,
        strokeWidth: 5,
        borderColor: Colors.white,
        borderStrokeWidth: border ? 2 : 0,
      );

  void _recenter() {
    setState(() => _follow = true);
    final shown = _shown;
    if (_ready && shown != null) {
      _map.move(shown, _zoom, offset: _centerOffset);
    }
  }

  @override
  void dispose() {
    _glide.dispose();
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final here = _shown;
    final accuracy = _shownAccuracy;
    final heading = _shownHeading;
    final tail = _tail;
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: here ?? _fallbackCenter,
            initialZoom: _zoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              _ready = true;
              final shown = _shown;
              if (shown != null) {
                _map.move(shown, _zoom, offset: _centerOffset);
              }
            },
            onPositionChanged: (_, hasGesture) {
              if (hasGesture && _follow) setState(() => _follow = false);
            },
          ),
          children: [
            MapTiles.layer(),
            // Tail outline under the trail, tail fill over it: the two
            // read as one line, with no white seam where they meet.
            if (tail != null) PolylineLayer(polylines: [_line(tail)]),
            _trailLayer,
            if (tail != null)
              PolylineLayer(polylines: [_line(tail, border: false)]),
            if (here != null && accuracy != null && accuracy > 0)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: here,
                    radius: accuracy,
                    useRadiusInMeter: true,
                    color: _dotColor.withValues(alpha: 0.12),
                    borderColor: _dotColor.withValues(alpha: 0.35),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
            if (here != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: here,
                    width: 44,
                    height: 44,
                    child: _RiderDot(headingDeg: heading),
                  ),
                ],
              ),
          ],
        ),
        // Required by the OpenStreetMap tile licence.
        Positioned(
          left: 6,
          bottom: widget.bottomInset + 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            color: Colors.white.withValues(alpha: 0.75),
            child: const Text(
              '© OpenStreetMap',
              style: TextStyle(fontSize: 9, color: Color(0xFF555555)),
            ),
          ),
        ),
        if (!_follow && here != null)
          Positioned(
            right: 12,
            bottom: widget.bottomInset + 12,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              tooltip: 'Follow my location',
              backgroundColor: Colors.white,
              foregroundColor: _dotColor,
              onPressed: _recenter,
              child: const Icon(Icons.my_location),
            ),
          ),
        if (here == null)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.white.withValues(alpha: 0.55),
              child: Center(
                child: Text('Waiting for GPS…', style: displayStyle(size: 20)),
              ),
            ),
          ),
      ],
    );
  }
}

/// The blue "you are here" dot, with an arrow the way the rider is going
/// once that's known.
class _RiderDot extends StatelessWidget {
  const _RiderDot({this.headingDeg});

  final double? headingDeg;

  @override
  Widget build(BuildContext context) {
    final heading = headingDeg;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (heading != null)
          Transform.rotate(
            angle: heading * math.pi / 180,
            child: const CustomPaint(
              size: Size.square(44),
              painter: _HeadingPainter(),
            ),
          ),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: _LiveRideMapState._dotColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(color: Color(0x40000000), blurRadius: 6),
            ],
          ),
        ),
      ],
    );
  }
}

/// A pointer above the dot's centre, i.e. facing north before rotation.
class _HeadingPainter extends CustomPainter {
  const _HeadingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final path = Path()
      ..moveTo(c.dx, c.dy - 21)
      ..lineTo(c.dx + 9, c.dy - 6)
      ..lineTo(c.dx - 9, c.dy - 6)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(path, Paint()..color = _LiveRideMapState._dotColor);
  }

  @override
  bool shouldRepaint(_HeadingPainter old) => false;
}
