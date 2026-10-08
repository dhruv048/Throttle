import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/rider_avatar.dart';
import '../widgets/tracked_route_map.dart';
import '../widgets/ui.dart';
import 'share_ride_screen.dart';

class RideDetailScreen extends StatelessWidget {
  const RideDetailScreen({super.key, required this.item});

  final FeedItem item;

  @override
  Widget build(BuildContext context) {
    final r = item.ride;
    final rider = item.rider;
    final when = r.rodeAt?.toLocal();
    String? uid;
    try {
      uid = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {}
    final mine = item.pending || (uid != null && rider.id == uid);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(r.title, style: displayStyle(size: 20)),
        actions: [
          if (mine)
            IconButton(
              tooltip: 'Share as image',
              icon: const Icon(Icons.ios_share),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => ShareRideScreen(item: item)),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          TrackedRouteMap.track(item.points, height: 360),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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
                      Text(
                        [
                          if (when != null) _date(when),
                          if (item.bikeName?.isNotEmpty == true) item.bikeName!,
                          if (item.pending)
                            'Waiting to sync'
                          else
                            r.visibility.label,
                        ].join(' · '),
                        style: monoStyle(size: 11, tracking: 0),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (r.startPlace != null && r.endPlace != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text('${r.startPlace} → ${r.endPlace}',
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.mutedForeground)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatBlock(
                            value: r.distanceKm.toStringAsFixed(2),
                            label: 'km',
                            valueSize: 28),
                      ),
                      Expanded(
                        child: StatBlock(
                            value: formatDuration(r.movingTimeSecs),
                            label: 'moving time',
                            valueSize: 28),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                          child: StatBlock(
                              value: r.avgSpeedKmh.toStringAsFixed(1),
                              label: 'avg km/h')),
                      Expanded(
                          child: StatBlock(
                              value: r.maxSpeedKmh.round().toString(),
                              label: 'top km/h')),
                      Expanded(
                          child: StatBlock(
                              value: formatNumber(r.elevationM.round()),
                              label: 'm climbed')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (!item.pending)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                '${r.kudosCount} kudos · ${r.commentsCount} comments',
                style: monoStyle(size: 11, tracking: 0),
              ),
            ),
        ],
      ),
    );
  }

  static String _date(DateTime t) {
    const months = [
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
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.day} ${months[t.month - 1]} ${t.year}, $hh:$mm';
  }
}
