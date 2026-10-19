import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:latlong2/latlong.dart';

import '../format.dart';
import '../models/models.dart';
import '../providers/core.dart';
import '../providers/journal.dart';
import '../repositories/journal_repository.dart';
import '../services/media_placement.dart';
import '../theme.dart';
import '../widgets/media_viewer.dart';
import '../widgets/skeleton.dart';
import '../widgets/tracked_route_map.dart';
import '../widgets/ui.dart';
import 'ride_detail_screen.dart' show formatRideDate;
import '../units.dart';

/// A ride told as a story: the route with photos and videos pinned where
/// they happened, in the order they happened, and the rider's own words.
/// The rider adds and edits; everyone who can see the ride can read it.
class RideJournalScreen extends ConsumerStatefulWidget {
  const RideJournalScreen({super.key, required this.item});

  final FeedItem item;

  @override
  ConsumerState<RideJournalScreen> createState() => _RideJournalScreenState();
}

/// A journal photo or video with its place on the route.
class _Entry {
  const _Entry(this.media, this.index);

  final RideMedia media;

  /// Into the track; null if it isn't on the route.
  final int? index;
}

class _RideJournalScreenState extends ConsumerState<RideJournalScreen> {
  late final List<TrackPoint> _track = widget.item.points;
  late final List<double> _km = distanceAlongKm(_track);

  /// While adding: how many of how many are done.
  ({int done, int total})? _adding;

  String get _rideId => widget.item.ride.id;
  RideJournalNotifier get _journal =>
      ref.read(rideJournalProvider(_rideId).notifier);

  /// Placed ones in route order, then the rest in the order they were taken.
  List<_Entry> _entries(List<RideMedia> media) {
    final placed = <_Entry>[];
    final unplaced = <_Entry>[];
    for (final m in media) {
      if (m.placed && _track.isNotEmpty) {
        placed.add(_Entry(m, nearestIndex(_track, m.lat!, m.lng!)));
      } else {
        unplaced.add(_Entry(m, null));
      }
    }
    placed.sort((a, b) => a.index!.compareTo(b.index!));
    return [...placed, ...unplaced];
  }

  Future<void> _addMedia() async {
    final List<XFile> files;
    try {
      files = await ref.read(pickJournalMediaProvider)();
    } catch (e) {
      _say('Couldn\'t open your photos: $e');
      return;
    }
    if (files.isEmpty || !mounted) return;

    var added = 0, unplaced = 0, skipped = 0, failed = 0;
    setState(() => _adding = (done: 0, total: files.length));
    for (final file in files) {
      final ext = JournalRepository.extensionFor(file.name, file.mimeType);
      try {
        if (ext == null) {
          skipped++;
          continue;
        }
        final bytes = await file.readAsBytes();
        if (bytes.length > JournalRepository.maxBytes) {
          skipped++;
          continue;
        }
        final meta = JournalRepository.isVideo(ext)
            ? const PhotoMeta()
            : readPhotoMeta(bytes);
        final place = placeOnRoute(_track,
            lat: meta.lat, lng: meta.lng, takenAt: meta.takenAt);
        final at = place == null ? null : _track[place.index];
        await _journal.add(
          bytes: bytes,
          extension: ext,
          lat: at?.lat,
          lng: at?.lng,
          takenAt: meta.takenAt,
        );
        added++;
        if (place == null) unplaced++;
      } catch (e) {
        debugPrint('Journal upload failed: $e');
        failed++;
      } finally {
        if (mounted) {
          setState(
              () => _adding = (done: _adding!.done + 1, total: files.length));
        }
      }
    }
    if (!mounted) return;
    setState(() => _adding = null);
    _say([
      if (added > 0) 'Added $added.',
      if (unplaced > 0)
        unplaced == 1
            ? '1 doesn\'t say where it was taken: place it on the route.'
            : '$unplaced don\'t say where they were taken: place them on the route.',
      if (skipped > 0)
        '$skipped skipped (photos and videos up to 50 MB: JPEG, PNG, HEIC, MP4, MOV).',
      if (failed > 0) '$failed couldn\'t upload. Check your connection.',
    ].join(' '));
  }

  void _say(String message) {
    if (!mounted || message.isEmpty) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editMemories(String? current) async {
    final text = await _editText(
      title: 'About the ride',
      initial: current ?? '',
      hint: 'The roads, the stops, the people, the weather… '
          'what you\'ll remember about this ride.',
      maxLength: 5000,
      minLines: 6,
    );
    if (text == null) return;
    try {
      await _journal.setText(text);
    } catch (_) {
      _say('Couldn\'t save. Check your connection.');
    }
  }

  Future<void> _editCaption(RideMedia media) async {
    final text = await _editText(
      title: 'Caption',
      initial: media.caption ?? '',
      hint: 'What was happening here?',
      maxLength: 500,
      minLines: 2,
    );
    if (text == null) return;
    try {
      await _journal.edit(media, caption: text);
    } catch (_) {
      _say('Couldn\'t save. Check your connection.');
    }
  }

  Future<String?> _editText({
    required String title,
    required String initial,
    required String hint,
    required int maxLength,
    required int minLines,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _TextEditSheet(
        title: title,
        initial: initial,
        hint: hint,
        maxLength: maxLength,
        minLines: minLines,
      ),
    );
  }

  Future<void> _place(_Entry entry) async {
    if (_track.isEmpty) return;
    final index = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PlaceOnRouteSheet(
        track: _track,
        km: _km,
        media: entry.media,
        initial: entry.index ?? _track.length - 1,
      ),
    );
    if (index == null) return;
    try {
      await _journal.edit(entry.media,
          lat: _track[index].lat, lng: _track[index].lng);
    } catch (_) {
      _say('Couldn\'t move it. Check your connection.');
    }
  }

  Future<void> _delete(RideMedia media) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            Text(media.isVideo ? 'Remove this video?' : 'Remove this photo?'),
        content: const Text('It will be removed from the ride\'s journal.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _journal.remove(media);
    } catch (_) {
      _say('Couldn\'t remove it. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final r = item.ride;
    final state = ref.watch(rideJournalProvider(_rideId));
    final journal = state.value;
    final uid = ref.watch(currentUserIdProvider);
    final mine = uid != null && item.rider.id == uid;
    final entries = journal == null ? null : _entries(journal.media);
    final ordered = [for (final e in entries ?? const <_Entry>[]) e.media];
    final placed = entries?.where((e) => e.index != null).toList() ?? const [];
    final unplaced =
        entries?.where((e) => e.index == null).toList() ?? const [];
    final when = r.rodeAt?.toLocal();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Ride Journal', style: displayStyle(size: 20)),
      ),
      bottomNavigationBar: mine ? _addBar() : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (when != null)
                  LabelMono(formatRideDate(when), color: AppColors.primary),
                const SizedBox(height: 4),
                Text(r.title, style: displayStyle(size: 30)),
                const SizedBox(height: 6),
                Text(
                  [
                    context.units.shortText(r.distanceKm),
                    formatDuration(r.movingTimeSecs),
                    '${context.units.speedText(r.maxSpeedKmh)} top speed',
                    if (item.bikeName?.isNotEmpty == true) item.bikeName!,
                  ].join(' · '),
                  style: monoStyle(size: 11, tracking: 0),
                ),
              ],
            ),
          ),
          TrackedRouteMap.track(
            _track,
            height: 280,
            pins: [
              for (var i = 0; i < placed.length; i++)
                Marker(
                  point: LatLng(_track[placed[i].index!].lat,
                      _track[placed[i].index!].lng),
                  width: 30,
                  height: 30,
                  child: GestureDetector(
                    onTap: () => openMediaViewer(context, ordered, i),
                    child: _NumberPin(i + 1, video: placed[i].media.isVideo),
                  ),
                ),
            ],
          ),
          if (journal == null && state.isLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Shimmer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 90, height: 10),
                    SizedBox(height: 10),
                    SkeletonBox(height: 14),
                    SizedBox(height: 6),
                    SkeletonBox(width: 220, height: 14),
                    SizedBox(height: 20),
                    AspectRatio(aspectRatio: 4 / 3, child: SkeletonBox()),
                  ],
                ),
              ),
            )
          else if (journal == null)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Couldn\'t load the journal. Try again in a moment.',
                  style: TextStyle(color: AppColors.mutedForeground)),
            )
          else ...[
            _memories(journal.text, mine: mine),
            if (placed.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 10),
                child: LabelMono('Along the route'),
              ),
              for (var i = 0; i < placed.length; i++)
                _entry(placed[i],
                    number: i + 1, ordered: ordered, at: i, mine: mine),
            ],
            if (unplaced.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                child: LabelMono(
                    mine ? 'Not on the route yet' : 'More from the ride'),
              ),
              for (var i = 0; i < unplaced.length; i++)
                _entry(unplaced[i],
                    ordered: ordered, at: placed.length + i, mine: mine),
            ],
            if (journal.media.isEmpty && mine)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.add_photo_alternate_outlined,
                          color: AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Add photos and videos from the ride. Ones taken '
                          'on the ride go where they were taken on the route.',
                          style: monoStyle(size: 12, tracking: 0),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _memories(String? text, {required bool mine}) {
    final has = text?.trim().isNotEmpty == true;
    if (!has && !mine) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: LabelMono('About the ride')),
              if (mine)
                TextButton.icon(
                  onPressed: () => _editMemories(text),
                  icon: Icon(has ? Icons.edit_outlined : Icons.add, size: 16),
                  label: Text(has ? 'Edit' : 'Write'),
                ),
            ],
          ),
          if (has)
            Text(text!.trim(),
                style: const TextStyle(fontSize: 16, height: 1.55))
          else
            GestureDetector(
              onTap: () => _editMemories(text),
              child: Text(
                'What will you remember about this ride? The roads, the '
                'stops, the people…',
                style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                    color: AppColors.mutedForeground.withValues(alpha: 0.9)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _entry(_Entry entry,
      {int? number,
      required List<RideMedia> ordered,
      required int at,
      required bool mine}) {
    final m = entry.media;
    final index = entry.index;
    final time =
        (m.takenAt ?? (index == null ? null : _track[index].t))?.toLocal();
    final where = [
      if (index != null)
        '${context.units.fixed(_km[index], 1)} ${context.units.distanceUnit} in',
      if (time != null)
        '${time.hour.toString().padLeft(2, '0')}:'
            '${time.minute.toString().padLeft(2, '0')}',
    ].join(' · ');
    return Padding(
      key: ValueKey(m.id),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (number != null) ...[
                _NumberPin(number, video: m.isVideo, size: 24),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                    where.isEmpty ? (m.isVideo ? 'Video' : 'Photo') : where,
                    style: monoStyle(size: 11, tracking: 0)),
              ),
              if (mine)
                PopupMenuButton<VoidCallback>(
                  tooltip: 'Options',
                  icon: const Icon(Icons.more_horiz,
                      color: AppColors.mutedForeground),
                  onSelected: (action) => action(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: () => _editCaption(m),
                      child: Text(m.caption?.isNotEmpty == true
                          ? 'Edit caption'
                          : 'Add caption'),
                    ),
                    if (_track.isNotEmpty)
                      PopupMenuItem(
                        value: () => _place(entry),
                        child: Text(
                            index == null ? 'Place on route' : 'Move on route'),
                      ),
                    PopupMenuItem(
                      value: () => _delete(m),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => openMediaViewer(context, ordered, at),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: MediaThumb(m, iconSize: 40),
              ),
            ),
          ),
          if (m.caption?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(m.caption!,
                  style: const TextStyle(fontSize: 15, height: 1.45)),
            )
          else if (mine)
            TextButton(
              onPressed: () => _editCaption(m),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: const Text('Add a caption'),
            ),
          if (mine && index == null && _track.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _place(entry),
              icon: const Icon(Icons.place_outlined, size: 18),
              label: const Text('Place on route'),
            ),
        ],
      ),
    );
  }

  Widget _addBar() {
    final adding = _adding;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: adding == null ? _addMedia : null,
            icon: adding == null
                ? const Icon(Icons.add_photo_alternate_outlined)
                : const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
            label: Text(
              adding == null
                  ? 'ADD PHOTOS & VIDEOS'
                  : 'ADDING ${adding.done + 1 > adding.total ? adding.total : adding.done + 1} OF ${adding.total}…',
              style: displayStyle(size: 18, color: Colors.white),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.7),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A numbered pin for a photo (orange) or video (dark) on the route.
class _NumberPin extends StatelessWidget {
  const _NumberPin(this.number, {this.video = false, this.size = 30});

  final int number;
  final bool video;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: video ? AppColors.foreground : AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
              color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Text('$number',
          style: TextStyle(
              fontSize: size * 0.42,
              fontWeight: FontWeight.w700,
              color: Colors.white)),
    );
  }
}

/// Slide along the route to where a photo or video was taken.
class _PlaceOnRouteSheet extends StatefulWidget {
  const _PlaceOnRouteSheet({
    required this.track,
    required this.km,
    required this.media,
    required this.initial,
  });

  final List<TrackPoint> track;
  final List<double> km;
  final RideMedia media;
  final int initial;

  @override
  State<_PlaceOnRouteSheet> createState() => _PlaceOnRouteSheetState();
}

class _PlaceOnRouteSheetState extends State<_PlaceOnRouteSheet> {
  late int _index = widget.initial.clamp(0, widget.track.length - 1);

  @override
  Widget build(BuildContext context) {
    final p = widget.track[_index];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                      width: 44,
                      height: 44,
                      child: MediaThumb(widget.media, iconSize: 16)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Where was this?', style: displayStyle(size: 20)),
                      Text('Slide along the route',
                          style: monoStyle(size: 11, tracking: 0)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: IgnorePointer(
                child: TrackedRouteMap.track(
                  widget.track,
                  height: 220,
                  interactive: false,
                  pins: [
                    Marker(
                      point: LatLng(p.lat, p.lng),
                      width: 30,
                      height: 30,
                      child: const _NumberPin(1, size: 30),
                    ),
                  ],
                ),
              ),
            ),
            Slider(
              value: _index.toDouble(),
              min: 0,
              max: (widget.track.length - 1).toDouble(),
              activeColor: AppColors.primary,
              onChanged: (v) => setState(() => _index = v.round()),
            ),
            Center(
              child: Text(
                  '${context.units.fixed(widget.km[_index], 1)} '
                  '${context.units.distanceUnit} in',
                  style: displayStyle(size: 18)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _index),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('PUT IT HERE',
                    style: displayStyle(size: 18, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Writes or edits a piece of text (memories, a caption); pops with it on
/// SAVE.
class _TextEditSheet extends StatefulWidget {
  const _TextEditSheet({
    required this.title,
    required this.initial,
    required this.hint,
    required this.maxLength,
    required this.minLines,
  });

  final String title;
  final String initial;
  final String hint;
  final int maxLength;
  final int minLines;

  @override
  State<_TextEditSheet> createState() => _TextEditSheetState();
}

class _TextEditSheetState extends State<_TextEditSheet> {
  // Disposed with the sheet, after it has animated away.
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: displayStyle(size: 22)),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: true,
              minLines: widget.minLines,
              maxLines: 12,
              maxLength: widget.maxLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: widget.hint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _text.text),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('SAVE',
                    style: displayStyle(size: 18, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
