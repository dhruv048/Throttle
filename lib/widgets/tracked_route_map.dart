import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';

class TrackedRouteMap extends StatelessWidget {
  const TrackedRouteMap({
    super.key,
    required this.points,
    this.height = 220,
  });

  final List<LatLng> points;
  final double height;

  static const _interaction = InteractionOptions(
    flags: InteractiveFlag.pinchZoom |
        InteractiveFlag.doubleTapZoom |
        InteractiveFlag.scrollWheelZoom,
  );

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
                interactionOptions: _interaction,
              )
            : MapOptions(
                initialCameraFit: CameraFit.coordinates(
                  coordinates: points,
                  padding: const EdgeInsets.all(32),
                  maxZoom: 17,
                ),
                interactionOptions: _interaction,
              ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.wheelsclub.wheelsclub',
          ),
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
