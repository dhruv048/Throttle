import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../data.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/photo_picker.dart';
import '../widgets/route_map.dart';
import '../widgets/tracked_route_map.dart';

enum ShareBackground { bike, photo, map, plain }

/// Builds a 1080×1350 (4:5) ride image and hands it to the OS share sheet.
class ShareRideScreen extends StatefulWidget {
  const ShareRideScreen({super.key, required this.item});

  final FeedItem item;

  @override
  State<ShareRideScreen> createState() => _ShareRideScreenState();
}

class _ShareRideScreenState extends State<ShareRideScreen> {
  // The card is laid out at this logical size and captured at 3x.
  static const _canvas = Size(360, 450);
  static const _pixelRatio = 3.0;

  final _cardKey = GlobalKey();
  final _shareButtonKey = GlobalKey();
  late ShareBackground _background;
  PickedPhoto? _photo;
  bool _sharing = false;

  FeedItem get item => widget.item;
  bool get _hasTrack => item.points.length >= 2;
  bool get _hasBikePhoto => item.bikePhotoUrl != null;

  @override
  void initState() {
    super.initState();
    _background = _hasBikePhoto
        ? ShareBackground.bike
        : _hasTrack
            ? ShareBackground.map
            : ShareBackground.plain;
  }

  Future<void> _choosePhoto() async {
    final photo = await pickPhoto(context, title: 'Your photo');
    if (photo != null) {
      setState(() {
        _photo = photo;
        _background = ShareBackground.photo;
      });
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      // Let any just-loaded image paint before capturing.
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: _pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('Could not render image');

      final box =
          _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final origin =
          box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      final r = item.ride;
      final bike =
          item.bikeName?.isNotEmpty == true ? ' on my ${item.bikeName}' : '';
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(data.buffer.asUint8List(), mimeType: 'image/png')
        ],
        fileNameOverrides: [
          'throttle-ride-${DateTime.now().millisecondsSinceEpoch}.png'
        ],
        text:
            '${r.distanceKm.toStringAsFixed(1)} km ride$bike — recorded with Throttle',
        sharePositionOrigin: origin, // required on iPad
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn\'t share: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Share ride', style: displayStyle(size: 20)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _canvas.width / _canvas.height,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: FittedBox(
                        child: RepaintBoundary(
                          key: _cardKey,
                          child: SizedBox.fromSize(
                            size: _canvas,
                            child: _ShareCard(
                              item: item,
                              background: _background,
                              photoBytes: _photo?.bytes,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  if (_hasBikePhoto) _chip('Bike photo', ShareBackground.bike),
                  _chip(
                    _photo == null ? 'Your photo…' : 'Your photo',
                    ShareBackground.photo,
                    onTap: _photo == null ? _choosePhoto : null,
                  ),
                  if (_photo != null)
                    IconButton(
                      tooltip: 'Change photo',
                      onPressed: _choosePhoto,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                  if (_hasTrack) _chip('Route map', ShareBackground.map),
                  _chip('Plain', ShareBackground.plain),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SizedBox(
                key: _shareButtonKey,
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: _sharing ? null : _share,
                  icon: _sharing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.ios_share),
                  label: Text('SHARE',
                      style: displayStyle(size: 20, color: Colors.white)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, ShareBackground value, {VoidCallback? onTap}) {
    final on = _background == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: on,
        onSelected: (_) =>
            onTap != null ? onTap() : setState(() => _background = value),
        selectedColor: AppColors.accent,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: on ? AppColors.accentForeground : AppColors.mutedForeground,
        ),
        side: BorderSide(
            color: on
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.border),
        showCheckmark: false,
      ),
    );
  }
}

/// The image itself. Laid out at 360×450 logical pixels.
class _ShareCard extends StatelessWidget {
  const _ShareCard(
      {required this.item, required this.background, this.photoBytes});

  final FeedItem item;
  final ShareBackground background;
  final List<int>? photoBytes;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  @override
  Widget build(BuildContext context) {
    final r = item.ride;
    final when = r.rodeAt?.toLocal();
    final isMap = background == ShareBackground.map;
    final showTrace = !isMap && item.points.length >= 2;

    return Stack(
      fit: StackFit.expand,
      children: [
        _background(),
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
                Colors.black.withValues(alpha: isMap ? 0.8 : 0.75),
              ],
              stops: const [0, 0.22, 0.45, 1],
            ),
          ),
        ),
        if (showTrace)
          Positioned(
            top: 64,
            right: 16,
            width: 150,
            height: 130,
            child: CustomPaint(
              painter: TrackShapePainter(
                item.points,
                lineColor: Colors.white,
                casingColor: AppColors.primary,
                startColor: Colors.white,
                endColor: AppColors.primary,
                strokeWidth: 3,
                padding: 8,
                shadow: true,
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
              if (when != null)
                Text(
                  '${when.day} ${_months[when.month - 1]} ${when.year}',
                  style: monoStyle(size: 10, tracking: 0, color: Colors.white),
                ),
            ],
          ),
        ),
        Positioned(
          left: 18,
          right: 18,
          // Clear the map's "© OpenStreetMap" credit.
          bottom: isMap ? 30 : 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                r.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: displayStyle(
                    size: 16, color: Colors.white.withValues(alpha: 0.9)),
              ),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: r.distanceKm.toStringAsFixed(2),
                    style: displayStyle(size: 56, color: Colors.white),
                  ),
                  TextSpan(
                    text: ' km',
                    style: displayStyle(
                        size: 20, color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ]),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _stat(formatDuration(r.movingTimeSecs), 'time'),
                  _stat(r.avgSpeedKmh.toStringAsFixed(0), 'avg km/h'),
                  _stat(r.maxSpeedKmh.round().toString(), 'top km/h'),
                  _stat(formatNumber(r.elevationM.round()), 'm climb'),
                ],
              ),
              if (item.bikeName?.isNotEmpty == true) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.two_wheeler,
                        size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.bikeName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle(
                            size: 11, tracking: 0, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _background() {
    switch (background) {
      case ShareBackground.bike:
        return Image.network(item.bikePhotoUrl!,
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => _plain());
      case ShareBackground.photo:
        return photoBytes == null
            ? _plain()
            : Image.memory(Uint8List.fromList(photoBytes!), fit: BoxFit.cover);
      case ShareBackground.map:
        return IgnorePointer(
          child: TrackedRouteMap.track(
            item.points,
            height: _ShareRideScreenState._canvas.height,
            interactive: false,
            // Keep the route in the clear band between header and stats.
            fitPadding: const EdgeInsets.fromLTRB(28, 64, 28, 200),
          ),
        );
      case ShareBackground.plain:
        return _plain();
    }
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

  Widget _stat(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: displayStyle(size: 20, color: Colors.white)),
          Text(label.toUpperCase(),
              style: labelMono(color: Colors.white.withValues(alpha: 0.75))),
        ],
      ),
    );
  }
}
