import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show Marker;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../format.dart';
import '../models/models.dart';
import '../providers/core.dart';
import '../providers/journal.dart';
import '../providers/live.dart';
import '../providers/rides.dart';
import '../services/place_names.dart';
import '../theme.dart';
import '../widgets/ride_flag.dart';
import '../widgets/rider_avatar.dart';
import '../widgets/skeleton.dart';
import '../widgets/tracked_route_map.dart';
import '../widgets/ui.dart';
import '../widgets/media_viewer.dart';
import '../widgets/visibility_picker.dart';
import 'ride_journal_screen.dart';
import 'rider_profile_screen.dart';
import 'share_ride_screen.dart';
import '../units.dart';

/// One ride: its map (with the flag it planted), the rider's title and
/// words, stats, the ride card and photos. Counts stay live, and it says so
/// if the ride is deleted while it's open. The rider can change who sees
/// their own rides, or delete them, here.
class RideDetailScreen extends ConsumerStatefulWidget {
  const RideDetailScreen({super.key, required this.item});

  final FeedItem item;

  @override
  ConsumerState<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends ConsumerState<RideDetailScreen> {
  /// Who can see it, once changed here.
  RideVisibility? _visibility;
  bool _changingVisibility = false;

  Future<void> _changeVisibility(FeedItem item) async {
    final current = _visibility ?? item.ride.visibility;
    final picked = await showVisibilitySheet(context, current);
    if (picked == null || picked == current || !mounted) return;
    setState(() {
      _visibility = picked;
      _changingVisibility = true;
    });
    try {
      final r = item.ride;
      await ref.read(rideRepositoryProvider).setVisibility(picked,
          rideId: item.pending ? null : r.id,
          localId: item.pending ? r.id : r.localId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _visibility = current);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Couldn\'t change who can see it. Check your connection.')));
    } finally {
      if (mounted) setState(() => _changingVisibility = false);
    }
  }

  Future<void> _delete(FeedItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this ride?'),
        content: const Text(
            'It will be removed from your profile and stats, with its '
            'photos and journal.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final rides = ref.read(rideRepositoryProvider);
      if (item.pending) {
        final saved = (await rides.myPendingRides())
            .where((p) => p.localId == item.ride.id)
            .firstOrNull;
        if (saved != null) await rides.deleteSavedRide(saved);
      } else {
        await rides.deleteRide(item.ride.id);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Couldn\'t delete it. Check your connection.')));
    }
  }

  /// [item] with its full track, once loaded: lists only load a preview of
  /// it. Shown with the preview until then.
  FeedItem _withFullTrack(FeedItem item) {
    if (!item.previewTrack || item.pending) return item;
    final track = ref.watch(rideTrackProvider(item.ride.id)).value;
    return track == null || track.isEmpty ? item : item.withTrack(track);
  }

  /// [item] with its full track, waiting for it if it's still loading (the
  /// journal places photos on it; ride cards draw it).
  Future<FeedItem> _full(FeedItem item) async {
    if (!item.previewTrack || item.pending) return item;
    try {
      final track = await ref.read(rideTrackProvider(item.ride.id).future);
      return track.isEmpty ? item : item.withTrack(track);
    } catch (_) {
      return item; // the preview will do
    }
  }

  Future<void> _openJournal(FeedItem item) async {
    final full = await _full(item);
    if (!mounted) return;
    await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => RideJournalScreen(item: full)));
  }

  Future<void> _share(FeedItem item) async {
    final full = await _full(item);
    if (!mounted) return;
    await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ShareRideScreen(item: full)));
  }

  @override
  Widget build(BuildContext context) {
    final item = _withFullTrack(watchLiveRide(ref, widget.item));
    final deleted = ref.watch(
        deletedRidesProvider.select((ids) => ids.contains(item.ride.id)));
    final r = item.ride;
    final rider = item.rider;
    final when = r.rodeAt?.toLocal();
    final uid = ref.watch(currentUserIdProvider);
    final mine = item.pending || (uid != null && rider.id == uid);
    final visibility = _visibility ?? r.visibility;
    // Rides on the phone have no journal until they upload.
    final journal =
        item.pending ? null : ref.watch(rideJournalProvider(r.id)).value;
    final media = journal?.media ?? const <RideMedia>[];
    final story = (journal == null ? r.journal : journal.text)?.trim();
    final flag = item.flag;
    // The ride card first, then the photos and videos, all in one viewer.
    final gallery = [
      if (r.cardImageUrl != null)
        RideMedia(
          id: 'card',
          rideId: r.id,
          userId: r.userId,
          kind: MediaKind.photo,
          url: r.cardImageUrl!,
          storagePath: '',
          caption: 'Ride card',
        ),
      ...media,
    ];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(r.title, style: displayStyle(size: 20)),
        actions: [
          if (mine && !deleted) ...[
            IconButton(
              tooltip: 'Share as image',
              icon: const Icon(Icons.ios_share),
              onPressed: () => _share(item),
            ),
            PopupMenuButton<VoidCallback>(
              tooltip: 'More',
              onSelected: (action) => action(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: () => _delete(item),
                  child: const Text('Delete ride'),
                ),
              ],
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (deleted)
            Container(
              width: double.infinity,
              color: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: const Text('This ride has been deleted.',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.accentForeground)),
            ),
          TrackedRouteMap.track(
            item.points,
            height: 360,
            pins: [
              if (flag != null && item.points.length >= 2)
                flagMarker(flag, size: 34),
              for (var i = 0; i < media.length; i++)
                if (media[i].placed)
                  Marker(
                    point: LatLng(media[i].lat!, media[i].lng!),
                    width: 28,
                    height: 28,
                    child: GestureDetector(
                      onTap: () => openMediaViewer(
                          context, gallery, gallery.indexOf(media[i])),
                      child: _MediaPin(video: media[i].isVideo),
                    ),
                  ),
            ],
          ),
          InkWell(
            onTap: item.pending ? null : () => openRiderProfile(context, rider),
            child: Padding(
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
                            if (item.bikeName?.isNotEmpty == true)
                              item.bikeName!,
                            if (item.pending)
                              'Waiting to sync'
                            else if (!mine)
                              visibility.label,
                          ].join(' · '),
                          style: monoStyle(size: 11, tracking: 0),
                        ),
                      ],
                    ),
                  ),
                  if (mine && !deleted)
                    _VisibilityButton(
                      visibility: visibility,
                      busy: _changingVisibility,
                      onTap: () => _changeVisibility(item),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(r.title, style: displayStyle(size: 26)),
          ),
          if (placesLine(r.startPlace, r.endPlace) case final where?)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Row(
                children: [
                  const Icon(Icons.flag_rounded,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(where,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.mutedForeground)),
                  ),
                ],
              ),
            ),
          if (story != null && story.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(story,
                  style: const TextStyle(fontSize: 15, height: 1.5)),
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
                            value: context.units.fixed(r.distanceKm, 2),
                            label: context.units.distanceUnit,
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
                              value: context.units.speedText(r.avgSpeedKmh),
                              label: 'avg speed')),
                      Expanded(
                          child: StatBlock(
                              value: context.units.speedText(r.maxSpeedKmh),
                              label: 'top speed')),
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
                // Comments are hidden until they can be read and written.
                // '${r.kudosCount} kudos · ${r.commentsCount} comments',
                '${r.kudosCount} kudos',
                style: monoStyle(size: 11, tracking: 0),
              ),
            ),
          if (gallery.isNotEmpty || (mine && !item.pending && !deleted))
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: _Gallery(
                gallery: gallery,
                hasCard: r.cardImageUrl != null,
                onAdd: mine && !item.pending && !deleted
                    ? () => _openJournal(item)
                    : null,
              ),
            ),
          if (!deleted)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _JournalSection(
                item: item,
                journal: journal,
                mine: mine,
                onOpen: () => _openJournal(item),
              ),
            ),
        ],
      ),
    );
  }

  static String _date(DateTime t) => formatRideDate(t);
}

/// Who can see the rider's own ride; tap to change it.
class _VisibilityButton extends StatelessWidget {
  const _VisibilityButton(
      {required this.visibility, required this.busy, required this.onTap});

  final RideVisibility visibility;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Who can see this ride: ${visibility.label}',
      child: Material(
        color: AppColors.card,
        shape: const StadiumBorder(side: BorderSide(color: AppColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(visibilityIcon(visibility),
                        size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(visibility.label,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                const Icon(Icons.expand_more,
                    size: 16, color: AppColors.mutedForeground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "9 Oct 2026, 06:30"
String formatRideDate(DateTime t) {
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

/// The ride card the rider posted with the ride, then its photos and
/// videos, in a row; tap one to see them all full screen.
class _Gallery extends StatelessWidget {
  const _Gallery({required this.gallery, required this.hasCard, this.onAdd});

  final List<RideMedia> gallery;

  /// The first is the ride card.
  final bool hasCard;

  /// The rider's own: adds more, from the journal.
  final VoidCallback? onAdd;

  static const _width = 128.0;
  static const _height = 160.0;

  @override
  Widget build(BuildContext context) {
    final count = gallery.length - (hasCard ? 1 : 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Expanded(child: LabelMono('Photos & memories')),
              if (count > 0)
                Text('$count', style: monoStyle(size: 11, tracking: 0)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _height,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (var i = 0; i < gallery.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                _tile(context, i),
              ],
              if (onAdd != null) ...[
                if (gallery.isNotEmpty) const SizedBox(width: 10),
                _addTile(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, int i) {
    final card = hasCard && i == 0;
    return Semantics(
      image: true,
      button: true,
      label: card ? 'Ride card' : (gallery[i].isVideo ? 'Video' : 'Photo'),
      child: GestureDetector(
        onTap: () => openMediaViewer(context, gallery, i),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: _width,
            height: _height,
            child: card
                ? NetworkPhoto(gallery[i].url)
                : MediaThumb(gallery[i], iconSize: 26),
          ),
        ),
      ),
    );
  }

  Widget _addTile() {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(14),
        child: CustomPaint(
          painter: const DashedRRectPainter(radius: 14),
          child: const SizedBox(
            width: _width,
            height: _height,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_photo_alternate_outlined,
                    size: 28, color: AppColors.primary),
                SizedBox(height: 6),
                Text('Add photos',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.foreground)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where a journal photo (or video) was taken, on the ride's map.
class _MediaPin extends StatelessWidget {
  const _MediaPin({this.video = false});

  final bool video;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: video ? AppColors.foreground : AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
              color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Icon(video ? Icons.videocam : Icons.photo_camera,
          size: 13, color: Colors.white),
    );
  }
}

/// The way into the ride's journal (its photos where they happened on the
/// route): an invitation for the rider while it's empty.
class _JournalSection extends StatelessWidget {
  const _JournalSection({
    required this.item,
    required this.journal,
    required this.mine,
    required this.onOpen,
  });

  final FeedItem item;

  /// Null while loading, or for a ride still on the phone.
  final RideJournal? journal;
  final bool mine;
  final VoidCallback onOpen;

  /// "3 photos · 1 video"
  static String _count(List<RideMedia> media) {
    final videos = media.where((m) => m.isVideo).length;
    final photos = media.length - videos;
    return [
      if (photos > 0) '$photos photo${photos == 1 ? '' : 's'}',
      if (videos > 0) '$videos video${videos == 1 ? '' : 's'}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if (item.pending) {
      return mine
          ? Text(
              'Photos added to this ride go up with it, and you can add more '
              'to its journal once it uploads.',
              style: monoStyle(size: 11, tracking: 0))
          : const SizedBox.shrink();
    }
    final journal = this.journal;
    if (journal == null || (journal.isEmpty && !mine)) {
      return const SizedBox.shrink();
    }
    final empty = journal.isEmpty;
    return GestureDetector(
      onTap: onOpen,
      child: AppCard(
        highlight: empty,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                  color: AppColors.accent, shape: BoxShape.circle),
              child: const Icon(Icons.auto_stories_outlined,
                  color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (empty)
                    Text('Start a Ride Journal', style: displayStyle(size: 18))
                  else
                    Row(
                      children: [
                        const LabelMono('Ride Journal'),
                        if (journal.media.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(_count(journal.media),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: monoStyle(size: 11, tracking: 0)),
                          ),
                        ],
                      ],
                    ),
                  const SizedBox(height: 4),
                  Text(
                    empty
                        ? 'Turn this ride into a story: photos and videos '
                            'where they happened, and what you\'ll remember.'
                        : 'The ride as a story: its photos where they '
                            'happened on the route.',
                    style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.mutedForeground),
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
