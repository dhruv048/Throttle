import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data.dart';
import '../models/models.dart';
import '../repositories/bike_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/ride_repository.dart';
import '../services/ride_events.dart';
import '../theme.dart';
import '../widgets/bike_form_sheet.dart';
import '../widgets/ride_card.dart';
import '../widgets/rider_avatar.dart';
import '../widgets/ui.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Profile? _profile;
  List<BikeRecord> _bikes = [];
  int? _rideCount;
  List<FeedItem> _recent = [];
  int? _followers;
  int? _following;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    RideEvents.changed.addListener(_loadData);
    _loadData();
  }

  @override
  void dispose() {
    RideEvents.changed.removeListener(_loadData);
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      setState(() => _loading = true);

      final profileRepo = ProfileRepository();
      final bikeRepo = BikeRepository();
      final rideRepo = RideRepository();

      final results = await Future.wait([
        profileRepo.getById(uid),
        bikeRepo.listForUser(uid),
        rideRepo.countForUser(uid),
        profileRepo.followCounts(uid),
        rideRepo.myPendingRides(),
        rideRepo.myRides(limit: 3),
      ]);

      if (mounted) {
        final follows = results[3] as ({int followers, int following});
        setState(() {
          _profile = results[0] as Profile?;
          _bikes = results[1] as List<BikeRecord>;
          _rideCount =
              (results[2] as int) + (results[4] as List<PendingRide>).length;
          _followers = follows.followers;
          _following = follows.following;
          final me = _profile ?? Profile(id: uid);
          final uploaded = [
            for (final f in results[5] as List<FeedItem>) f.ride.localId,
          ].whereType<String>().toSet();
          _recent = [
            for (final p in results[4] as List<PendingRide>)
              if (!uploaded.contains(p.localId))
                FeedItem(
                  ride: p.toRecord(),
                  rider: me,
                  bikeName: p.bikeName,
                  points: p.points,
                  pending: true,
                ),
            ...results[5] as List<FeedItem>,
          ].take(3).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed == true) {
      await Supabase.instance.client.auth.signOut();
    }
  }

  Future<void> _editBike([BikeRecord? bike]) async {
    final saved = await showBikeFormSheet(
      context,
      bike: bike,
      defaultPrimary: _bikes.isEmpty,
    );
    if (saved) await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _profile?.displayName ?? _profile?.username ?? '';
    final initials = _profile?.initials ?? '';
    final subtitle = [
      if (_profile?.city?.isNotEmpty == true) _profile!.city!,
      if (_profile?.username != null) '@${_profile!.username}',
    ].join(' · ');

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        children: [
          RiseIn(
            child: Row(
              children: [
                RiderAvatar(initials: initials, size: 64),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: displayStyle(size: 30)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: monoStyle(size: 11, tracking: 0)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _signOut(context),
                  icon: const Icon(Icons.logout, size: 20),
                  tooltip: 'Sign out',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                _col(_count(_followers), 'followers'),
                _col(_count(_following), 'following'),
                _col(_count(_rideCount), 'rides'),
              ],
            ),
          ),
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: 24),
            const LabelMono('Recent rides'),
            const SizedBox(height: 8),
            for (final item in _recent)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: RideCard(key: ValueKey(item.ride.id), item: item),
              ),
            Text('All your rides are in Activity.',
                style: monoStyle(size: 11, tracking: 0)),
          ],
          const SizedBox(height: 24),
          const LabelMono('Garage'),
          const SizedBox(height: 8),
          if (_loading && _bikes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ..._bikes.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => _editBike(b),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (b.photoUrl != null)
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.network(
                            b.photoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const ColoredBox(color: AppColors.panel),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                    child: Text(b.name,
                                        style: displayStyle(size: 20))),
                                if (b.isPrimary)
                                  const LabelMono('Primary',
                                      color: AppColors.primary),
                                const SizedBox(width: 8),
                                const Icon(Icons.edit_outlined,
                                    size: 16, color: AppColors.mutedForeground),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (b.year != null) '${b.year}',
                                '${formatDistance(b.riddenKm)} km ridden',
                                if (b.odometerKm > b.riddenKm)
                                  'odo ${formatNumber(b.odometerKm.round())} km',
                              ].join(' · '),
                              style: monoStyle(size: 11, tracking: 0),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          InkWell(
            onTap: _editBike,
            borderRadius: BorderRadius.circular(16),
            child: CustomPaint(
              painter: _DashedRRectPainter(),
              child: const SizedBox(
                width: double.infinity,
                height: 56,
                child: Center(
                  child: Text(
                    '+ Add motorcycle',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.mutedForeground),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const LabelMono('Privacy'),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Default ride visibility',
                        style: TextStyle(fontSize: 14)),
                    Text('Followers',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('Hide start & end near home',
                        style: TextStyle(fontSize: 14)),
                    Text('On',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _count(int? n) => n == null ? '–' : formatNumber(n);

  Widget _col(String v, String l) {
    return Expanded(
      child: Column(
        children: [
          Text(v, style: displayStyle(size: 24)),
          const SizedBox(height: 4),
          LabelMono(l),
        ],
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final next = math.min(dist + dash, metric.length);
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
