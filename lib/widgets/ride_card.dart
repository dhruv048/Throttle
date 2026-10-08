import 'package:flutter/material.dart';

import '../data.dart';
import '../models/models.dart';
import '../repositories/ride_repository.dart';
import '../screens/ride_detail_screen.dart';
import '../theme.dart';
import 'rider_avatar.dart';
import 'tracked_route_map.dart';
import 'ui.dart';

class RideCard extends StatefulWidget {
  const RideCard({super.key, required this.item});

  final FeedItem item;

  @override
  State<RideCard> createState() => _RideCardState();
}

class _RideCardState extends State<RideCard> {
  late FeedItem item = widget.item;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant RideCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.item, widget.item)) item = widget.item;
  }

  Future<void> _toggleKudos() async {
    if (_busy || item.pending) return;
    final before = item;
    final liked = !before.likedByMe;
    setState(() {
      _busy = true;
      item = before.copyWith(
        likedByMe: liked,
        kudosCount: before.ride.kudosCount + (liked ? 1 : -1),
      );
    });
    try {
      final repo = RideRepository();
      liked
          ? await repo.giveKudos(before.ride.id)
          : await repo.removeKudos(before.ride.id);
    } catch (_) {
      if (mounted) setState(() => item = before);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RideDetailScreen(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = item.ride;
    final rider = item.rider;
    final when = r.rodeAt;
    final subtitle = [
      if (when != null) timeAgo(when),
      if (item.bikeName != null && item.bikeName!.isNotEmpty) item.bikeName!,
    ].join(' · ');
    final liked = item.likedByMe;
    return GestureDetector(
      onTap: _open,
      behavior: HitTestBehavior.opaque,
      child: AppCard(
        clip: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  RiderAvatar(initials: rider.initials),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rider.displayName ?? rider.username ?? 'Rider',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(subtitle, style: monoStyle(size: 11, tracking: 0)),
                      ],
                    ),
                  ),
                  if (item.pending)
                    const LabelMono('Waiting to sync', color: AppColors.primary)
                  else if (r.visibility != RideVisibility.public)
                    Icon(
                      r.visibility == RideVisibility.private
                          ? Icons.lock_outline
                          : Icons.group_outlined,
                      size: 14,
                      color: AppColors.mutedForeground,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title, style: displayStyle(size: 18)),
                  if (r.startPlace != null && r.endPlace != null)
                    Text('${r.startPlace} → ${r.endPlace}',
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.mutedForeground)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                      child: StatBlock(
                          value: formatKm(r.distanceKm), label: 'km')),
                  Expanded(
                      child: StatBlock(
                          value: formatDuration(r.movingTimeSecs),
                          label: 'time')),
                  Expanded(
                    child: StatBlock(
                        value: formatNumber(r.elevationM.round()),
                        label: 'm elev'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // The card handles taps; the map is a static preview.
            IgnorePointer(
              child: TrackedRouteMap.track(item.points,
                  height: 160, interactive: false),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _toggleKudos,
                    child: Row(
                      children: [
                        Icon(
                          liked ? Icons.favorite : Icons.favorite_border,
                          size: 16,
                          color: liked
                              ? AppColors.primary
                              : AppColors.mutedForeground,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${r.kudosCount}',
                          style: TextStyle(
                            fontSize: 14,
                            color: liked
                                ? AppColors.primary
                                : AppColors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  const Icon(Icons.chat_bubble_outline,
                      size: 16, color: AppColors.mutedForeground),
                  const SizedBox(width: 6),
                  Text('${r.commentsCount}',
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.mutedForeground)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
