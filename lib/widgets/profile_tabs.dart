import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../format.dart';
import '../models/models.dart';
import '../providers/core.dart';
import '../providers/rider.dart';
import '../screens/ride_detail_screen.dart';
import '../theme.dart';
import 'map_tiles.dart';
import 'media_viewer.dart';
import 'ride_card.dart';
import 'ride_flag.dart';
import 'skeleton.dart';
import 'ui.dart';
import '../units.dart';

/// What a profile shows under the rider's header.
enum ProfileTab {
  activities('Activities', Icons.route_outlined),
  memories('Memories', Icons.photo_library_outlined),
  flags('Flags', Icons.flag_outlined),
  garage('Garage', Icons.two_wheeler_outlined);

  const ProfileTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The profile's tabs, pinned to the top as the profile scrolls.
class ProfileTabsHeader extends SliverPersistentHeaderDelegate {
  ProfileTabsHeader(
      {required this.tabs, required this.tab, required this.onChanged});

  final List<ProfileTab> tabs;
  final ProfileTab tab;
  final ValueChanged<ProfileTab> onChanged;

  double get _height => tabs.length > 3 ? 70 : 60;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(
              color: shrinkOffset > 0 || overlapsContent
                  ? AppColors.border
                  : Colors.transparent),
        ),
      ),
      child: ProfileTabBar(tabs: tabs, tab: tab, onChanged: onChanged),
    );
  }

  @override
  bool shouldRebuild(covariant ProfileTabsHeader old) =>
      old.tab != tab || old.onChanged != onChanged || old.tabs != tabs;
}

class ProfileTabBar extends StatelessWidget {
  const ProfileTabBar(
      {super.key,
      required this.tabs,
      required this.tab,
      required this.onChanged});

  final List<ProfileTab> tabs;
  final ProfileTab tab;
  final ValueChanged<ProfileTab> onChanged;

  @override
  Widget build(BuildContext context) {
    // Four don't fit side by side with their icons: icons go on top.
    final stacked = tabs.length > 3;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final t in tabs)
            Expanded(child: _segment(t, on: t == tab, stacked: stacked)),
        ],
      ),
    );
  }

  Widget _segment(ProfileTab t, {required bool on, required bool stacked}) {
    final icon = Icon(t.icon,
        size: stacked ? 18 : 16,
        color: on ? AppColors.primary : AppColors.mutedForeground);
    final label = Text(
      t.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontSize: stacked ? 11.5 : 13,
          fontWeight: FontWeight.w600,
          color: on ? AppColors.foreground : AppColors.mutedForeground),
    );
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: () => onChanged(t),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: stacked ? 48 : 38,
          decoration: BoxDecoration(
            color: on ? AppColors.card : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: on
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: stacked
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [icon, const SizedBox(height: 2), label],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    icon,
                    const SizedBox(width: 6),
                    Flexible(child: label),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A plain note in place of a tab's content (loading failed, nothing yet).
class TabMessage extends StatelessWidget {
  const TabMessage(this.text, {super.key, this.icon, this.title});

  final String text;
  final IconData? icon;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                  color: AppColors.accent, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: displayStyle(size: 18)),
                  const SizedBox(height: 4),
                ],
                Text(text,
                    style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: AppColors.mutedForeground)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rides as cards, a page at a time.
class RideListSliver extends StatelessWidget {
  const RideListSliver({
    super.key,
    required this.rides,
    required this.loading,
    required this.empty,
    this.error,
    this.loadingMore = false,
    this.riderTappable = false,
  });

  /// Null until loaded.
  final List<FeedItem>? rides;
  final bool loading;

  /// Shown when there are none.
  final String empty;

  /// Shown when they couldn't be loaded.
  final String? error;
  final bool loadingMore;
  final bool riderTappable;

  @override
  Widget build(BuildContext context) {
    final rides = this.rides;
    if (rides == null) {
      return SliverToBoxAdapter(
        child: loading
            ? const RideListSkeleton()
            : TabMessage(error ?? 'Couldn\'t load rides. Pull down to retry.'),
      );
    }
    if (rides.isEmpty) {
      return SliverToBoxAdapter(
        child: TabMessage(empty, icon: Icons.route_outlined),
      );
    }
    return SliverList.builder(
      itemCount: rides.length + (loadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == rides.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final item = rides[i];
        return Padding(
          key: ValueKey(item.ride.id),
          padding: const EdgeInsets.only(bottom: 12),
          child: RideCard(item: item, riderTappable: riderTappable),
        );
      },
    );
  }
}

/// A rider's memories: every photo and video from their rides (that this
/// rider may see), newest first, three to a row. Tap one to see them all.
class MemoriesSliver extends ConsumerWidget {
  const MemoriesSliver({super.key, required this.riderId, this.mine = false});

  final String riderId;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(riderMemoriesProvider(riderId));
    final pages = state.value;
    if (pages == null) {
      return SliverToBoxAdapter(
        child: state.isLoading
            ? const _GridSkeleton()
            : const TabMessage('Couldn\'t load memories. Pull down to retry.'),
      );
    }
    final media = pages.items;
    if (media.isEmpty) {
      return SliverToBoxAdapter(
        child: TabMessage(
          mine
              ? 'Add photos and videos when you finish a ride, or to any '
                  'ride\'s journal. They\'ll all be here.'
              : 'Photos and videos from their rides will show here.',
          icon: Icons.photo_library_outlined,
          title: 'No memories yet',
        ),
      );
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: media.length,
          itemBuilder: (context, i) => _MemoryTile(
            key: ValueKey(media[i].id),
            media: media[i],
            onTap: () => openMediaViewer(context, media, i),
          ),
        ),
        if (pages.loadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({super.key, required this.media, required this.onTap});

  final RideMedia media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      image: true,
      label: [
        media.isVideo ? 'Video' : 'Photo',
        if (media.rideTitle != null) 'from ${media.rideTitle}',
      ].join(' '),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: MediaThumb(media, iconSize: 22),
        ),
      ),
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [for (var i = 0; i < 6; i++) const SkeletonBox(radius: 8)],
      ),
    );
  }
}

/// A rider's flags on a map: one where each ride reached furthest. [extra]
/// adds flags of rides still on this phone (the rider's own).
class FlagsSliver extends ConsumerWidget {
  const FlagsSliver({
    super.key,
    required this.riderId,
    this.extra = const [],
    this.mine = false,
  });

  final String riderId;
  final List<RideFlag> extra;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(riderFlagsProvider(riderId));
    final loaded = state.value;
    final Widget child;
    if (loaded == null && state.isLoading) {
      child = const Shimmer(child: SkeletonBox(height: 380, radius: 16));
    } else if (loaded == null && extra.isEmpty) {
      child = const TabMessage('Couldn\'t load flags. Pull down to retry.');
    } else {
      final flags = [...extra, ...?loaded];
      child = flags.isEmpty
          ? TabMessage(
              mine
                  ? 'Every ride plants a flag at the furthest point you '
                      'reach. Finish a ride to plant your first.'
                  : 'Every ride plants a flag at the furthest point it '
                      'reached. Theirs will show here.',
              icon: Icons.flag_outlined,
              title: 'No flags yet',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppCard(
                  child: FlagsMap(
                    flags: flags,
                    height: 380,
                    onExpand: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FlagsMapScreen(flags: flags),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Each flag marks the furthest point a ride reached. Tap '
                  'one to see the ride.',
                  style: monoStyle(size: 11, tracking: 0),
                ),
              ],
            );
    }
    return SliverToBoxAdapter(child: child);
  }
}

/// [flags] full screen, to pan and zoom around.
class FlagsMapScreen extends StatelessWidget {
  const FlagsMapScreen({super.key, required this.flags});

  final List<RideFlag> flags;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Flags', style: displayStyle(size: 20))),
      body: FlagsMap(flags: flags, fullScreen: true),
    );
  }
}

/// Opens the ride behind [flag]: one still on this phone, or loaded.
Future<void> openFlagRide(
    BuildContext context, WidgetRef ref, RideFlag flag) async {
  FeedItem? item;
  try {
    final rides = ref.read(rideRepositoryProvider);
    if (flag.pending) {
      final ride = (await rides.myPendingRides())
          .where((p) => p.localId == flag.rideId)
          .firstOrNull;
      if (ride != null) {
        item = FeedItem(
          ride: ride.toRecord(),
          rider: ref.read(myProfileProvider).value ??
              Profile(id: ref.read(currentUserIdProvider) ?? ''),
          bikeName: ride.bikeName,
          points: ride.points,
          pending: true,
        );
      }
    } else {
      item = await rides.feedItem(flag.rideId);
    }
  } catch (_) {
    item = null;
  }
  if (!context.mounted) return;
  if (item == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Couldn\'t open this ride. Try again in a moment.')));
    return;
  }
  await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RideDetailScreen(item: item!)));
}

/// Flags on a map; tap one for its ride.
class FlagsMap extends ConsumerStatefulWidget {
  const FlagsMap({
    super.key,
    required this.flags,
    this.height,
    this.onExpand,
    this.fullScreen = false,
  });

  final List<RideFlag> flags;

  /// Null fills the space it's given.
  final double? height;

  /// Shows a button to open it full screen.
  final VoidCallback? onExpand;

  /// Dragging pans the map; otherwise (inside a scrolling page) it takes
  /// two fingers, so one still scrolls the page.
  final bool fullScreen;

  @override
  ConsumerState<FlagsMap> createState() => _FlagsMapState();
}

class _FlagsMapState extends ConsumerState<FlagsMap> {
  RideFlag? _selected;
  bool _opening = false;

  Future<void> _open(RideFlag flag) async {
    setState(() => _opening = true);
    await openFlagRide(context, ref, flag);
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final flags = widget.flags;
    final points = [for (final f in flags) LatLng(f.lat, f.lng)];
    final selected = _selected;
    final map = FlutterMap(
      options: MapOptions(
        initialCenter: points.first,
        initialZoom: 12,
        initialCameraFit: points.length > 1
            ? CameraFit.coordinates(
                coordinates: points,
                padding: const EdgeInsets.fromLTRB(40, 70, 40, 40),
                maxZoom: 13,
              )
            : null,
        interactionOptions: InteractionOptions(
          flags: widget.fullScreen
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.pinchZoom |
                  InteractiveFlag.pinchMove |
                  InteractiveFlag.doubleTapZoom |
                  InteractiveFlag.scrollWheelZoom,
        ),
        onTap: (_, __) => setState(() => _selected = null),
      ),
      children: [
        MapTiles.layer(),
        MarkerLayer(
          markers: [
            // The one picked on top.
            for (final f in flags)
              if (f != selected)
                flagMarker((lat: f.lat, lng: f.lng),
                    key: ValueKey(f.rideId),
                    onTap: () => setState(() => _selected = f)),
            if (selected != null)
              flagMarker((lat: selected.lat, lng: selected.lng),
                  key: ValueKey(selected.rideId), selected: true),
          ],
        ),
        // Required by the OpenStreetMap tile licence.
        Align(
          alignment: Alignment.bottomRight,
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            color: Colors.white.withValues(alpha: 0.75),
            child: const Text('© OpenStreetMap',
                style: TextStyle(fontSize: 9, color: Color(0xFF555555))),
          ),
        ),
      ],
    );
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          Positioned.fill(child: map),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
              decoration: BoxDecoration(
                color: AppColors.foreground.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.flag_rounded,
                      size: 15, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    '${formatNumber(flags.length)} '
                    '${flags.length == 1 ? 'FLAG' : 'FLAGS'}',
                    style: labelMono(size: 11, color: Colors.white)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          if (widget.onExpand != null)
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 2,
                child: IconButton(
                  tooltip: 'Full screen',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.open_in_full, size: 18),
                  onPressed: widget.onExpand,
                ),
              ),
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 22,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: selected == null
                  ? const SizedBox.shrink()
                  : FlagCard(
                      key: ValueKey(selected.rideId),
                      flag: selected,
                      opening: _opening,
                      onOpen: () => _open(selected),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The ride behind a flag: where it reached, what it's called, when, how
/// far.
class FlagCard extends StatelessWidget {
  const FlagCard({
    super.key,
    required this.flag,
    required this.opening,
    required this.onOpen,
  });

  final RideFlag flag;
  final bool opening;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final when = flag.rodeAt?.toLocal();
    return Material(
      color: AppColors.card,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: opening ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              const PlantedFlag(size: 30),
              const SizedBox(width: 10),
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
                        if (when != null) formatRideDate(when),
                        context.units.shortText(flag.distanceKm),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(size: 11, tracking: 0),
                    ),
                  ],
                ),
              ),
              opening
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('View ride',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary)),
                          Icon(Icons.chevron_right,
                              size: 18, color: AppColors.primary),
                        ],
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
