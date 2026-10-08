import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/models.dart';
import '../theme.dart';
import 'map_tiles.dart';

class TrackedRouteMap extends StatelessWidget {
  const TrackedRouteMap({
    super.key,
    required this.points,
    this.height = 220,
    this.interactive = true,
    this.fitPadding,
  });

  /// Map for a saved ride's track (downsampled for long rides).
  factory TrackedRouteMap.track(
    List<TrackPoint> track, {
    Key? key,
    double height = 220,
    bool interactive = true,
    EdgeInsets? fitPadding,
  }) {
    const maxPoints = 400;
    final step = (track.length / maxPoints).ceil().clamp(1, track.length + 1);
    final pts = <LatLng>[
      for (var i = 0; i < track.length; i += step)
        LatLng(track[i].lat, track[i].lng),
      if (track.isNotEmpty && (track.length - 1) % step != 0)
        LatLng(track.last.lat, track.last.lng),
    ];
    return TrackedRouteMap(
      key: key,
      points: pts,
      height: height,
      interactive: interactive,
      fitPadding: fitPadding,
    );
  }

  final List<LatLng> points;
  final double height;

  /// False for previews inside scrolling lists, so the list keeps the drag.
  final bool interactive;

  /// Space to keep clear around the route when fitting the camera, e.g. to
  /// keep it out from under overlaid text.
  final EdgeInsets? fitPadding;

  static const _interaction = InteractionOptions(
    flags: InteractiveFlag.pinchZoom |
        InteractiveFlag.doubleTapZoom |
        InteractiveFlag.scrollWheelZoom,
  );

  static const _static = InteractionOptions(flags: InteractiveFlag.none);

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: ColoredBox(
          color: AppColors.panel,
          child: Center(
            child: Text(
              'No GPS track recorded',
              style: monoStyle(size: 11, tracking: 0),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: FlutterMap(
        options: points.length == 1
            ? MapOptions(
                initialCenter: points.first,
                initialZoom: 16,
                interactionOptions: interactive ? _interaction : _static,
              )
            : MapOptions(
                initialCameraFit: CameraFit.coordinates(
                  coordinates: points,
                  padding: fitPadding ?? EdgeInsets.all(height < 160 ? 18 : 32),
                  maxZoom: 17,
                ),
                interactionOptions: interactive ? _interaction : _static,
              ),
        children: [
          MapTiles.layer(),
          if (points.length > 1)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: points,
                  color: AppColors.primary,
                  strokeWidth: 4,
                  borderColor: AppColors.card,
                  borderStrokeWidth: 3,
                ),
              ],
            ),
          MarkerLayer(
            markers: [
              Marker(
                point: points.first,
                width: 14,
                height: 14,
                child: const _Dot(color: Color(0xFF2F9E44)),
              ),
              if (points.length > 1)
                Marker(
                  point: points.last,
                  width: 14,
                  height: 14,
                  child: const _Dot(color: Color(0xFFC92A2A)),
                ),
            ],
          ),
          // Required by the OpenStreetMap tile licence.
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              margin: const EdgeInsets.all(4),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              color: Colors.white.withValues(alpha: 0.75),
              child: const Text(
                '© OpenStreetMap',
                style: TextStyle(fontSize: 9, color: Color(0xFF555555)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }
}
