import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models/models.dart';
import '../providers/live.dart';
import '../services/place_names.dart';
import '../screens/ride_detail_screen.dart';
import '../screens/rider_profile_screen.dart';
import '../theme.dart';
import 'rider_avatar.dart';
import 'tracked_route_map.dart';
import 'ui.dart';
import '../units.dart';

/// A ride in a list. Its kudos and comment counts stay live: the same ride
/// can be on several screens at once, and they all keep in step.
class RideCard extends ConsumerWidget {
  const RideCard({super.key, required this.item, this.riderTappable = true});

  final FeedItem item;

  /// Tapping the rider opens their profile (not when it's already open).
  final bool riderTappable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = watchLiveRide(ref, this.item);
    final r = item.ride;
    final rider = item.rider;
    final when = r.rodeAt;
    final subtitle = [
      if (when != null) timeAgo(when),
      if (item.bikeName != null && item.bikeName!.isNotEmpty) item.bikeName!,
    ].join(' · ');
    final liked = item.likedByMe;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => RideDetailScreen(item: item)),
      ),
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
                  Expanded(
                    child: GestureDetector(
                      // The card itself opens the ride.
                      onTap: riderTappable && !item.pending
                          ? () => openRiderProfile(context, rider)
                          : null,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          RiderAvatar(initials: rider.initials),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    rider.displayName ??
                                        rider.username ??
                                        'Rider',
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600)),
                                Text(subtitle,
                                    style: monoStyle(size: 11, tracking: 0)),
                              ],
                            ),
                          ),
                        ],
                      ),
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
                  if (placesLine(r.startPlace, r.endPlace) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.flag_rounded,
                              size: 14, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(placesLine(r.startPlace, r.endPlace)!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.mutedForeground)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                      child: StatBlock(
                          value: context.units.short(r.distanceKm),
                          label: context.units.distanceUnit)),
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
                    onTap: () => ref
                        .read(rideCountersProvider.notifier)
                        .toggleKudos(item),
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
                  // Comments are hidden until they can be read and written.
                  // const SizedBox(width: 20),
                  // const Icon(Icons.chat_bubble_outline,
                  //     size: 16, color: AppColors.mutedForeground),
                  // const SizedBox(width: 6),
                  // Text('${r.commentsCount}',
                  //     style: const TextStyle(
                  //         fontSize: 14, color: AppColors.mutedForeground)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
