import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models/models.dart';
import '../providers/core.dart';
import '../providers/live.dart';
import '../providers/navigation.dart';
import '../providers/notifications.dart';
import '../providers/rider.dart';
import '../providers/rides.dart';
import '../services/place_names.dart';
import '../theme.dart';
import '../widgets/flags_globe.dart';
import '../widgets/profile_tabs.dart' show openFlagRide;
import '../widgets/ride_flag.dart';
import '../widgets/rider_avatar.dart';
import '../widgets/skeleton.dart';
import '../widgets/ui.dart';
import 'notifications_screen.dart';
import '../units.dart';

/// The rider's own home: their flags (every place their rides reached, on a
/// globe that drops into the map), riding next, and the places they've
/// been. Other riders' rides are a tap away in Discover.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  /// Reloads what Home shows; each part keeps its current (real) data until
  /// the new data arrives.
  static Future<void> refresh(WidgetRef ref) {
    final uid = ref.read(currentUserIdProvider);
    return refreshAll(ref, [
      myProfileProvider.future,
      myBikesProvider.future,
      myPendingRidesProvider.future,
      unreadNotificationCountProvider.future,
      if (uid != null) riderFlagsProvider(uid).future,
    ]);
  }

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Places of older rides are being named (once per session).
  bool _naming = false;

  static String _partOfDay(DateTime now) {
    if (now.hour < 12) return 'Morning';
    if (now.hour < 17) return 'Afternoon';
    return 'Evening';
  }

  /// The rider's flags: uploaded rides', and those of rides still on this
  /// phone. Null while they load.
  List<RideFlag>? _flags(String? uid) {
    if (uid == null) return const [];
    final state = ref.watch(riderFlagsProvider(uid));
    var uploaded = state.value;
    if (uploaded == null && state.hasError) {
      // Flags not set up on the server yet: from the rides themselves.
      uploaded = [
        for (final item
            in ref.watch(myRidesProvider).value?.items ?? const <FeedItem>[])
          if (item.flag != null)
            RideFlag(
              rideId: item.ride.id,
              title: item.ride.title,
              lat: item.flag!.lat,
              lng: item.flag!.lng,
              distanceKm: item.ride.distanceKm,
              rodeAt: item.ride.rodeAt,
              place: item.ride.endPlace,
              localId: item.ride.localId,
            ),
      ];
    }
    if (uploaded == null) return null;
    final known = uploaded.map((f) => f.localId).whereType<String>().toSet();
    final onPhone = [
      for (final p
          in ref.watch(myPendingRidesProvider).value ?? const <PendingRide>[])
        if (!known.contains(p.localId))
          RideFlag.fromRecord(p.toRecord(), pending: true),
    ].whereType<RideFlag>();
    if (!state.hasError) _nameUnnamed(uid, uploaded);
    return [...onPhone, ...uploaded];
  }

  /// Rides from before places were named get theirs.
  void _nameUnnamed(String uid, List<RideFlag> flags) {
    if (_naming || !flags.any((f) => f.place == null)) return;
    _naming = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final rides = ref.read(rideRepositoryProvider);
      final named = await nameReachedPlaces(
        ref.read(placeNamesProvider),
        flags,
        (id, place) {
          final flag = flags.firstWhere((f) => f.rideId == id);
          return rides.setPlaces(id,
              endPlace: place,
              // "Ride · 12.3 km" becomes "Ride to Nagarkot".
              title: PendingRide.isAutoTitle(flag.title)
                  ? PendingRide.placeTitle(place)
                  : null);
        },
      );
      if (named > 0 && mounted) {
        ref.invalidate(riderFlagsProvider(uid));
        ref.read(dataChangesProvider).rides(); // their new names, everywhere
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final partOfDay = _partOfDay(DateTime.now());
    final profileState = ref.watch(myProfileProvider);
    final profile = profileState.value;
    final loadingUser = profileState.isLoading && profile == null;
    final name = profile?.displayName ?? profile?.username ?? '';
    final firstName = name.split(' ').first;
    final flags = _flags(ref.watch(currentUserIdProvider));

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => HomeScreen.refresh(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              PageHeader(
                eyebrow: 'Good ${partOfDay.toLowerCase()}',
                title: '',
                titleWidget: loadingUser
                    // Wraps like the loaded greeting, so nothing overflows.
                    ? Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('$partOfDay, ', style: displayStyle(size: 34)),
                          const Shimmer(
                              child: SkeletonBox(width: 110, height: 30)),
                        ],
                      )
                    : Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: firstName.isEmpty
                                  ? partOfDay
                                  : '$partOfDay, ',
                              style: displayStyle(size: 34),
                            ),
                            TextSpan(
                              text: firstName,
                              style: displayStyle(
                                  size: 34, color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                right: Row(
                  children: [
                    _NotificationBell(
                      unread:
                          ref.watch(unreadNotificationCountProvider).value ?? 0,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const NotificationsScreen()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    loadingUser
                        ? const Shimmer(child: SkeletonBox.circle(size: 36))
                        : RiderAvatar(initials: profile?.initials ?? ''),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _startRide(),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FlagsGlobe(flags: flags),
              ),
              const SizedBox(height: 1),
              if (flags != null && flags.isNotEmpty) ...[
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _places(flags),
                ),
              ],
            ],
          ),
        ),
        // Positioned(
        //   left: 0,
        //   right: 0,
        //   bottom: 16,
        //   child: Center(
        //     child: _DiscoverButton(
        //       onTap: () =>
        //           ref.read(currentTabProvider.notifier).show(AppTab.discover),
        //     ),
        //   ),
        // ),
      ],
    );
  }

  Widget _startRide() {
    return SheenButton(
      onTap: () => ref.read(currentTabProvider.notifier).show(AppTab.record),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LabelMono('Ready to roll'),
                  const SizedBox(height: 4),
                  Text('Start Ride', style: displayStyle(size: 24)),
                  const SizedBox(height: 8),
                  _bikeLine(ref.watch(myBikesProvider)),
                ],
              ),
            ),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Lit from the top left, like the glint, so it reads as a
                // glossy button.
                gradient: RadialGradient(
                  center: const Alignment(-0.4, -0.5),
                  radius: 1.1,
                  colors: [
                    Color.lerp(AppColors.primary, Colors.white, 0.2)!,
                    AppColors.primary,
                    Color.lerp(AppColors.primary, Colors.black, 0.1)!,
                  ],
                  stops: const [0, 0.55, 1],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 18,
                    spreadRadius: -4,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 28),
            ),
          ],
        ),
      ),
    );
  }

  /// "Your primary bike" under Start Ride: a skeleton while loading, nothing
  /// if it couldn't load, and a prompt only when there really are no bikes.
  Widget _bikeLine(AsyncValue<List<BikeRecord>> bikesState) {
    final bikes = bikesState.value;
    if (bikes == null) {
      return bikesState.isLoading
          ? const Shimmer(child: SkeletonBox(width: 120, height: 11))
          : const SizedBox(height: 11);
    }
    final label = bikes.isEmpty
        ? 'Add a bike in Profile'
        : bikes.firstWhere((b) => b.isPrimary, orElse: () => bikes.first).name;
    return Row(
      children: [
        const BlinkDot(),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(size: 11, tracking: 0),
          ),
        ),
      ],
    );
  }

  /// The latest places the rider's rides reached.
  Widget _places(List<RideFlag> flags) {
    final latest = [...flags]..sort(
        (a, b) => (b.rodeAt ?? DateTime(0)).compareTo(a.rodeAt ?? DateTime(0)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LabelMono('Places you\'ve reached'),
        const SizedBox(height: 8),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < latest.length && i < 6; i++) ...[
                if (i > 0)
                  const Divider(height: 1, indent: 58, color: AppColors.border),
                _PlaceRow(
                  key: ValueKey(latest[i].rideId),
                  flag: latest[i],
                  onTap: () => openFlagRide(context, ref, latest[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({super.key, required this.flag, required this.onTap});

  final RideFlag flag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final when = flag.rodeAt;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(
          children: [
            const PlantedFlag(size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(flag.place ?? flag.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: displayStyle(size: 17)),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (flag.place != null) flag.title,
                      if (when != null) timeAgo(when),
                      context.units.shortText(flag.distanceKm),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(size: 11, tracking: 0),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.mutedForeground),
          ],
        ),
      ),
    );
  }
}

/// Floats over Home: other riders' rides are in Discover.
class _DiscoverButton extends StatelessWidget {
  const _DiscoverButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.foreground,
      elevation: 6,
      shadowColor: Colors.black38,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: const Padding(
          padding: EdgeInsets.fromLTRB(18, 13, 22, 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.explore, size: 20, color: AppColors.primary),
              SizedBox(width: 10),
              Text('Discover new rides',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bell on Home, with how many notifications are unread.
class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: unread > 0 ? 'Notifications, $unread new' : 'Notifications',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: AppColors.card,
            shape:
                const CircleBorder(side: BorderSide(color: AppColors.border)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                    unread > 0
                        ? Icons.notifications
                        : Icons.notifications_outlined,
                    size: 16,
                    color:
                        unread > 0 ? AppColors.primary : AppColors.foreground),
              ),
            ),
          ),
          if (unread > 0)
            Positioned(
              top: -4,
              right: -4,
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('unread-badge'),
                  constraints:
                      const BoxConstraints(minWidth: 18, minHeight: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.background, width: 2),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        color: AppColors.primaryForeground),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
