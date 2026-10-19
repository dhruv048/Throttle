import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models/models.dart';
import '../providers/core.dart';
import '../providers/live.dart';
import '../providers/navigation.dart';
import '../providers/rider.dart';
import '../providers/rides.dart';
import '../theme.dart';
import '../widgets/bike_chooser.dart';
import '../widgets/follow_button.dart';
import '../widgets/profile_tabs.dart';
import '../widgets/rider_avatar.dart';
import '../widgets/skeleton.dart';
import '../widgets/ui.dart';
import '../units.dart';

/// Opens [rider]'s profile page. What's already known about them shows
/// straight away while the rest loads.
void openRiderProfile(BuildContext context, Profile rider) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => RiderProfileScreen(riderId: rider.id, initial: rider),
  ));
}

/// Any rider's page: who they are, Follow, their garage, then their
/// activities (the rides you may see: followers-only ones once you follow
/// them), memories (their rides' photos) and flags (where their rides
/// reached).
class RiderProfileScreen extends ConsumerStatefulWidget {
  const RiderProfileScreen({super.key, required this.riderId, this.initial});

  final String riderId;

  /// What's already known (e.g. from a ride card), shown while loading.
  final Profile? initial;

  @override
  ConsumerState<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends ConsumerState<RiderProfileScreen> {
  ProfileTab _tab = ProfileTab.activities;

  String get riderId => widget.riderId;

  Future<void> _refresh() => refreshAll(ref, [
        riderProfileProvider(riderId).future,
        riderFollowCountsProvider(riderId).future,
        riderRideCountProvider(riderId).future,
        riderBikesProvider(riderId).future,
        riderRidesProvider(riderId).future,
        riderMemoriesProvider(riderId).future,
        riderFlagsProvider(riderId).future,
      ]);

  void _loadMore() {
    switch (_tab) {
      case ProfileTab.activities:
        ref.read(riderRidesProvider(riderId).notifier).loadMore();
      case ProfileTab.memories:
        ref.read(riderMemoriesProvider(riderId).notifier).loadMore();
      case ProfileTab.flags || ProfileTab.garage:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(riderProfileProvider(riderId));
    final countsState = ref.watch(riderFollowCountsProvider(riderId));
    final rideCountState = ref.watch(riderRideCountProvider(riderId));
    final bikesState = ref.watch(riderBikesProvider(riderId));
    final isMe = ref.watch(currentUserIdProvider) == riderId;

    final profile = profileState.value ?? widget.initial;
    final name = profile?.displayName ?? profile?.username ?? 'Rider';
    final counts = countsState.value;
    final notFound = profileState.hasValue && profileState.value == null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          profile?.username != null ? '@${profile!.username}' : name,
          style: displayStyle(size: 20),
        ),
      ),
      body: notFound
          ? Center(
              child: Text('This rider isn\'t on Throttle any more.',
                  style: monoStyle(size: 12, tracking: 0)),
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.axis == Axis.vertical &&
                      n.metrics.extentAfter < 600) {
                    _loadMore();
                  }
                  return false;
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      sliver: SliverList.list(
                        children: [
                          _header(profile, name, loading: profile == null),
                          if (profile?.bio?.trim().isNotEmpty == true) ...[
                            const SizedBox(height: 14),
                            Text(profile!.bio!.trim(),
                                style:
                                    const TextStyle(fontSize: 14, height: 1.4)),
                          ],
                          if (!isMe) ...[
                            const SizedBox(height: 16),
                            LayoutBuilder(
                              builder: (context, constraints) => FollowButton(
                                riderId: riderId,
                                width: constraints.maxWidth,
                                height: 42,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          AppCard(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Row(
                              children: [
                                _count(counts?.followers, 'followers'),
                                _count(counts?.following, 'following'),
                                _count(rideCountState.value, 'rides'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: ProfileTabsHeader(
                        tabs: ProfileTab.values,
                        tab: _tab,
                        onChanged: (t) => setState(() => _tab = t),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      sliver: switch (_tab) {
                        ProfileTab.activities => _activities(isMe),
                        ProfileTab.memories =>
                          MemoriesSliver(riderId: riderId, mine: isMe),
                        ProfileTab.flags =>
                          FlagsSliver(riderId: riderId, mine: isMe),
                        ProfileTab.garage => SliverToBoxAdapter(
                            child: _garage(bikesState, isMe: isMe),
                          ),
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _activities(bool isMe) {
    final ridesState = ref.watch(riderRidesProvider(riderId));
    final deleted = ref.watch(deletedRidesProvider);
    final pages = ridesState.value;
    return RideListSliver(
      rides: pages?.items.where((f) => !deleted.contains(f.ride.id)).toList(),
      loading: ridesState.isLoading,
      loadingMore: pages?.loadingMore ?? false,
      empty: isMe
          ? 'Your rides will show here.'
          : 'No rides to show yet. Riders can keep rides for their '
              'followers or just themselves.',
    );
  }

  static Widget _noTile(BikeRecord _) => const SizedBox.shrink();

  Widget _garage(AsyncValue<List<BikeRecord>> bikesState,
      {required bool isMe}) {
    final bikes = bikesState.value;
    if (bikes == null) {
      return bikesState.isLoading
          ? const BikeGrid(
              bikes: [], tile: _noTile, loading: true, padding: EdgeInsets.zero)
          : const TabMessage('Couldn\'t load bikes. Pull down to retry.');
    }
    if (bikes.isEmpty) {
      return TabMessage(
        isMe
            ? 'Add your motorcycle in Profile.'
            : 'No motorcycles in their garage yet.',
        icon: Icons.two_wheeler_outlined,
        title: 'Empty garage',
      );
    }
    return BikeGrid(
      bikes: bikes,
      padding: EdgeInsets.zero,
      tile: (b) => BikeTile(
        bike: b,
        badge: b.isPrimary ? 'Primary' : null,
        subtitle: '${context.units.totalText(b.riddenKm)} ridden',
      ),
    );
  }

  Widget _header(Profile? profile, String name, {required bool loading}) {
    if (loading) {
      return const Shimmer(
        child: Row(
          children: [
            SkeletonBox.circle(size: 72),
            SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 170, height: 28),
                SizedBox(height: 8),
                SkeletonBox(width: 120, height: 11),
              ],
            ),
          ],
        ),
      );
    }
    final details = [
      if (profile?.city?.isNotEmpty == true) profile!.city!,
      if (profile?.username != null) '@${profile!.username}',
    ].join(' · ');
    return Row(
      children: [
        RiderAvatar(initials: profile?.initials ?? '', size: 72),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: displayStyle(size: 30)),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(details, style: monoStyle(size: 11, tracking: 0)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _count(int? value, String label) {
    return Expanded(
      child: Column(
        children: [
          value == null
              ? const Shimmer(child: SkeletonBox(width: 40, height: 24))
              : Text(formatNumber(value), style: displayStyle(size: 24)),
          const SizedBox(height: 4),
          LabelMono(label),
        ],
      ),
    );
  }
}
