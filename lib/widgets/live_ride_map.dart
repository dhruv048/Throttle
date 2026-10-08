import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';
import 'map_tiles.dart';

/// Full-screen map for an in-progress ride: follows the rider, draws the
/// track as it grows, and shows the current fix with its accuracy circle.
///
/// [topInset]/[bottomInset] are the heights covered by overlays, so the
/// rider's dot is kept in the middle of the part of the map you can see.
class LiveRideMap extends StatefulWidget {
  const LiveRideMap({
    super.key,
    required this.trail,
    this.here,
    this.accuracyM,
    this.topInset = 0,
    this.bottomInset = 0,
  });

  final List<LatLng> trail;
  final LatLng? here;
  final double? accuracyM;
  final double topInset;
  final double bottomInset;

  @override
  State<LiveRideMap> createState() => _LiveRideMapState();
}

class _LiveRideMapState extends State<LiveRideMap> {
  static const _zoom = 16.5;
  // Used only until the first fix arrives.
  static const _fallbackCenter = LatLng(27.7172, 85.3240);

  final _map = MapController();
  bool _ready = false;
  bool _follow = true;

  Offset get _centerOffset =>
      Offset(0, (widget.topInset - widget.bottomInset) / 2);

  @override
  void didUpdateWidget(covariant LiveRideMap old) {
    super.didUpdateWidget(old);
    final here = widget.here;
    if (_ready && _follow && here != null && here != old.here) {
      _map.move(here, _map.camera.zoom, offset: _centerOffset);
    }
  }

  void _recenter() {
    setState(() => _follow = true);
    final here = widget.here;
    if (_ready && here != null) {
      _map.move(here, _zoom, offset: _centerOffset);
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final here = widget.here;
    final accuracy = widget.accuracyM;
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
              if (widget.here != null) {
                _map.move(widget.here!, _zoom, offset: _centerOffset);
              }
            },
            onPositionChanged: (_, hasGesture) {
              if (hasGesture && _follow) setState(() => _follow = false);
            },
          ),
          children: [
            MapTiles.layer(),
            if (widget.trail.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    // A fresh list each frame: the trail is appended in place.
                    points: List.of(widget.trail),
                    color: AppColors.primary,
                    strokeWidth: 5,
                    borderColor: Colors.white,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            if (here != null && accuracy != null && accuracy > 0)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: here,
                    radius: accuracy,
                    useRadiusInMeter: true,
                    color: const Color(0xFF2F80ED).withValues(alpha: 0.12),
                    borderColor:
                        const Color(0xFF2F80ED).withValues(alpha: 0.35),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
            if (here != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: here,
                    width: 22,
                    height: 22,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F80ED),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(color: Color(0x40000000), blurRadius: 6),
                        ],
                      ),
                    ),
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
              foregroundColor: const Color(0xFF2F80ED),
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
