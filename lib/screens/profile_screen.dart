import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models/models.dart';
import '../providers/core.dart';
import '../providers/navigation.dart';
import '../providers/rider.dart';
import '../providers/rides.dart';
import '../providers/settings.dart';
import '../theme.dart';
import '../widgets/bike_chooser.dart';
import '../widgets/bike_form_sheet.dart';
import '../widgets/profile_tabs.dart';
import '../widgets/rider_avatar.dart';
import '../widgets/skeleton.dart';
import '../widgets/ui.dart';
import '../units.dart';

/// The signed-in rider's own profile: who they are, their counts and
/// garage, then their activities, memories and flags, as other riders see
/// them (plus rides still on this phone).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  /// Reloads what Profile shows; it keeps showing the current (real) data
  /// until the new data arrives.
  static Future<void> refresh(WidgetRef ref) {
    final uid = ref.read(currentUserIdProvider);
    return refreshAll(ref, [
      myProfileProvider.future,
      myBikesProvider.future,
      myRideCountProvider.future,
      myFollowCountsProvider.future,
      myPendingRidesProvider.future,
      myRidesProvider.future,
      if (uid != null) ...[
        riderMemoriesProvider(uid).future,
        riderFlagsProvider(uid).future,
      ],
    ]);
  }

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  ProfileTab _tab = ProfileTab.activities;

  Future<void> _signOut() async {
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
      await ref.read(supabaseClientProvider).auth.signOut();
    }
  }

  void _loadMore(String? uid) {
    switch (_tab) {
      case ProfileTab.activities:
        ref.read(myRidesProvider.notifier).loadMore();
      case ProfileTab.memories:
        if (uid != null) {
          ref.read(riderMemoriesProvider(uid).notifier).loadMore();
        }
      case ProfileTab.flags || ProfileTab.garage:
        break;
    }
  }

  /// The rider's own profile: their flags are on Home.
  static const _tabs = [
    ProfileTab.activities,
    ProfileTab.memories,
    ProfileTab.garage,
  ];

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(myProfileProvider);
    final bikesState = ref.watch(myBikesProvider);
    final countState = ref.watch(myRideCountProvider);
    final followsState = ref.watch(myFollowCountsProvider);
    final pendingState = ref.watch(myPendingRidesProvider);
    final ridesState = ref.watch(myRidesProvider);
    final uid = ref.watch(currentUserIdProvider);

    final profile = profileState.value;
    final bikes = bikesState.value;
    final follows = followsState.value;
    final pending = pendingState.value;
    final pages = ridesState.value;
    final uploaded = pages?.items;
    final uploadedIds = (uploaded ?? const <FeedItem>[])
        .map((f) => f.ride.localId)
        .whereType<String>()
        .toSet();
    final unsynced =
        pending?.where((p) => !uploadedIds.contains(p.localId)).toList();
    final count = countState.value;
    final rideCount =
        count == null || unsynced == null ? null : count + unsynced.length;
    final me = profile ?? Profile(id: uid ?? '');
    final rides = uploaded == null || unsynced == null
        ? null
        : [
            for (final p in unsynced)
              FeedItem(
                ride: p.toRecord(),
                rider: me,
                bikeName: p.bikeName,
                points: p.points,
                pending: true,
              ),
            ...uploaded,
          ];

    final loadingProfile = profileState.isLoading && profile == null;
    final loadingCounts = followsState.isLoading ||
        countState.isLoading ||
        pendingState.isLoading;
    final failed = [
      profileState,
      bikesState,
      countState,
      followsState,
      pendingState,
      ridesState,
    ].any((state) => state.hasError);
    final error = !failed
        ? null
        : profile == null
            ? 'Couldn\'t load your profile. Pull down to retry.'
            : 'Couldn\'t refresh — showing what loaded earlier.';

    // Saving a bike reloads the bikes (and everything showing them).
    Future<void> editBike([BikeRecord? bike]) => showBikeFormSheet(
          context,
          bike: bike,
          defaultPrimary: bikes?.isEmpty ?? true,
        );

    return RefreshIndicator(
      onRefresh: () => ProfileScreen.refresh(ref),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 600) {
            _loadMore(uid);
          }
          return false;
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              sliver: SliverList.list(
                children: [
                  RiseIn(
                    child: Row(
                      children: [
                        if (loadingProfile)
                          const Expanded(
                            child: Shimmer(
                              child: Row(
                                children: [
                                  SkeletonBox.circle(size: 64),
                                  SizedBox(width: 16),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SkeletonBox(width: 170, height: 30),
                                      SizedBox(height: 8),
                                      SkeletonBox(width: 120, height: 11),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          )
                        else ...[
                          RiderAvatar(
                              initials: profile?.initials ?? '', size: 64),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    profile?.displayName ??
                                        profile?.username ??
                                        '',
                                    style: displayStyle(size: 30)),
                                const SizedBox(height: 4),
                                Text(
                                  [
                                    if (profile?.city?.isNotEmpty == true)
                                      profile!.city!,
                                    if (profile?.username != null)
                                      '@${profile!.username}',
                                  ].join(' · '),
                                  style: monoStyle(size: 11, tracking: 0),
                                ),
                              ],
                            ),
                          ),
                        ],
                        IconButton(
                          onPressed: _signOut,
                          icon: const Icon(Icons.logout, size: 20),
                          tooltip: 'Sign out',
                        ),
                      ],
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(error,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.mutedForeground)),
                    ),
                  if (follows != null && rideCount != null ||
                      loadingCounts) ...[
                    const SizedBox(height: 20),
                    AppCard(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        children: [
                          _col(follows?.followers, 'followers'),
                          _col(follows?.following, 'following'),
                          _col(rideCount, 'rides'),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const LabelMono('Units'),
                  const SizedBox(height: 8),
                  AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Distance and speed',
                            style: TextStyle(fontSize: 14)),
                        const SizedBox(height: 10),
                        _UnitsPicker(
                          value: ref.watch(unitsProvider),
                          onChanged: ref.read(unitsProvider.notifier).set,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const LabelMono('Privacy'),
                  const SizedBox(height: 8),
                  // const AppCard(
                  //   padding: EdgeInsets.all(16),
                  //   child: Row(
                  //     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  //     children: [
                  //       Flexible(
                  //         child: Text('New rides default to',
                  //             style: TextStyle(fontSize: 14)),
                  //       ),
                  //       Text('Public',
                  //           style: TextStyle(
                  //               fontSize: 14, fontWeight: FontWeight.w600)),
                  //     ],
                  //   ),
                  // ),
                ],
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: ProfileTabsHeader(
                tabs: _tabs,
                tab: _tab,
                onChanged: (t) => setState(() => _tab = t),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              sliver: switch (_tab) {
                ProfileTab.activities => RideListSliver(
                    rides: rides,
                    loading: ridesState.isLoading || pendingState.isLoading,
                    loadingMore: pages?.loadingMore ?? false,
                    empty: 'No rides yet. Hit Record and go ride!',
                    error: 'Couldn\'t load your rides. Pull down to retry.',
                  ),
                ProfileTab.memories when uid != null =>
                  MemoriesSliver(riderId: uid, mine: true),
                ProfileTab.garage => SliverToBoxAdapter(
                    child: bikes == null && !bikesState.isLoading
                        ? const TabMessage(
                            'Couldn\'t load your bikes. Pull down to retry.')
                        : BikeGrid(
                            loading: bikes == null,
                            padding: EdgeInsets.zero,
                            bikes: bikes ?? const [],
                            tile: (b) => BikeTile(
                              bike: b,
                              editable: true,
                              onTap: () => editBike(b),
                              badge: b.isPrimary ? 'Primary' : null,
                              subtitle: [
                                '${context.units.totalText(b.riddenKm)} ridden',
                                if (b.year != null) '${b.year}',
                              ].join(' · '),
                            ),
                            onAdd: editBike,
                            addLabel: 'Add motorcycle',
                          ),
                  ),
                _ => const SliverToBoxAdapter(child: SizedBox.shrink()),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _col(int? value, String label) {
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

/// Kilometres or miles, as two segments.
class _UnitsPicker extends StatelessWidget {
  const _UnitsPicker({required this.value, required this.onChanged});

  final Units value;
  final ValueChanged<Units> onChanged;

  static const _labels = {
    Units.metric: 'Kilometres · km/h',
    Units.imperial: 'Miles · mph',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final u in Units.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: u == value,
                child: GestureDetector(
                  onTap: () => onChanged(u),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: u == value ? AppColors.card : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: u == value
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      _labels[u]!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: u == value
                              ? AppColors.foreground
                              : AppColors.mutedForeground),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
