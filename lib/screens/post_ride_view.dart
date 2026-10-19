import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../models/models.dart';
import '../providers/core.dart';
import '../providers/journal.dart';
import '../providers/navigation.dart';
import '../providers/recorder.dart';
import '../providers/rider.dart';
import '../services/place_names.dart';
import '../theme.dart';
import '../widgets/ride_celebration.dart';
import '../widgets/ride_flag.dart';
import '../widgets/share_card.dart';
import '../widgets/skeleton.dart';
import '../widgets/tracked_route_map.dart';
import '../widgets/ui.dart';
import '../widgets/visibility_picker.dart';
import 'ride_detail_screen.dart' show formatRideDate;
import 'share_ride_screen.dart';
import '../units.dart';

/// "00:42:10"
String clock(int s) {
  final h = (s ~/ 3600).toString().padLeft(2, '0');
  final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
  final sec = (s % 60).toString().padLeft(2, '0');
  return '$h:$m:$sec';
}

/// After FINISH: carry on if it was a mistake, then the ride as it'll be
/// posted (its map and stats, a title, what the rider wants to say about it,
/// the bike, the ride card and photos, who can see it) and SAVE RIDE, which
/// plants its flag. The actions stay pinned below the scrolling part.
class PostRideView extends ConsumerStatefulWidget {
  const PostRideView({super.key});

  @override
  ConsumerState<PostRideView> createState() => _PostRideViewState();
}

class _PostRideViewState extends ConsumerState<PostRideView> {
  /// The ride card's design. Share edits it too, so changes made there carry
  /// over to the card posted with the ride.
  late final ValueNotifier<ShareCardDesign> _card;
  final _cardKey = GlobalKey();

  /// The celebration has been shown for this ride.
  bool _celebrated = false;

  /// The card design last posted with the ride.
  ShareCardDesign? _postedDesign;
  late final TextEditingController _title;
  late final TextEditingController _story;

  /// Photos are being added.
  bool _adding = false;

  /// What happened to the last photos added, under them (a snack bar would
  /// cover the buttons).
  String? _mediaNote;

  FinishedRideNotifier get _finished => ref.read(finishedRideProvider.notifier);

  @override
  void initState() {
    super.initState();
    final finished = ref.read(finishedRideProvider)!;
    _card = ValueNotifier(ShareCardDesign.initial(finished.item));
    _title = TextEditingController(text: finished.customTitle);
    _story = TextEditingController(text: finished.ride.journal ?? '');
    // A different bike: the card shows its photo (unless it's the rider's
    // own photo).
    ref.listenManual(finishedRideProvider.select((f) => f?.bikePhotoUrl),
        (_, __) {
      final finished = ref.read(finishedRideProvider);
      final design = _card.value;
      if (finished == null || design.background == ShareBackground.photo) {
        return;
      }
      _card.value = ShareCardDesign(
          ShareCardDesign.initial(finished.item).background,
          photo: design.photo,
          style: design.style);
      _postCard();
    });
    // The flag goes in as soon as the ride's finished, while it saves
    // (once the Record tab is on screen: a ride restored at launch waits).
    ref.listenManual(currentTabProvider, (_, tab) {
      if (tab == AppTab.record) _celebrate();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(currentTabProvider) == AppTab.record) _celebrate();
      _postCard();
    });
  }

  @override
  void dispose() {
    _card.dispose();
    _title.dispose();
    _story.dispose();
    super.dispose();
  }

  /// Posts the ride card with the ride as it's now designed (the same
  /// image Share makes), if it's attached and has changed since it was last
  /// posted. If it can't be made, the ride goes without it.
  Future<void> _postCard() async {
    final finished = ref.read(finishedRideProvider);
    if (finished == null || !finished.attachCard) return;
    final design = _card.value;
    if (identical(design, _postedDesign)) return;
    _postedDesign = design;
    try {
      final jpeg = await renderShareCardJpeg(context,
          item: finished.item, design: design);
      if (!mounted || !identical(design, _card.value)) return;
      await _finished.setCard(jpeg);
    } catch (e) {
      debugPrint('Ride card failed: $e');
      if (identical(_postedDesign, design)) _postedDesign = null;
    }
  }

  /// Posts the ride card with the ride, or takes it off.
  void _setAttachCard(bool attach) {
    _postedDesign = null;
    _finished.setAttachCard(attach);
    if (attach) _postCard();
  }

  /// FINISH: its flag goes in, with what it earned, while it saves. From
  /// there the rider shares it, looks at it (this page), or is done.
  Future<void> _celebrate() async {
    final finished = ref.read(finishedRideProvider);
    if (_celebrated || !mounted || finished == null) return;
    if (!finished.worthSaving && !finished.saving && finished.saved == null) {
      return; // too short: saved only if the rider says so
    }
    _celebrated = true;
    await showRideCelebration(context);
  }

  /// Asks, then drops the ride (saved or not). False if it's kept.
  Future<bool> _confirmDiscard(BuildContext context) async {
    final finished = ref.read(finishedRideProvider);
    if (finished == null) return true;
    final trivial = finished.ride.distanceKm < FinishedRideNotifier.minKeepKm &&
        finished.ride.media.isEmpty;
    if (!trivial) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard this ride?'),
          content: const Text(
              'It will be deleted from your profile and stats, with the '
              'photos added to it.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Discard')),
          ],
        ),
      );
      if (ok != true) return false;
    }
    try {
      await _finished.discard();
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Couldn\'t delete it. Try again when online ($e)')));
      }
      return false;
    }
  }

  Future<void> _delete() => _confirmDiscard(context);

  /// Available as soon as the ride ends; doesn't wait for the save. The
  /// card picked there is the one posted with the ride.
  Future<void> _openShare() async {
    final finished = ref.read(finishedRideProvider);
    if (finished == null) return;
    hideKeyboard();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ShareRideScreen(item: finished.item, design: _card),
    ));
    if (mounted) _postCard();
  }

  Future<void> _addMedia() async {
    hideKeyboard();
    final List<XFile> files;
    try {
      files = await ref.read(pickJournalMediaProvider)();
    } catch (e) {
      _say('Couldn\'t open your photos: $e');
      return;
    }
    if (files.isEmpty || !mounted) return;
    setState(() {
      _adding = true;
      _mediaNote = null;
    });
    final result = await _finished.addMedia(files);
    if (!mounted) return;
    final note = [
      if (result.unplaced > 0)
        result.unplaced == 1
            ? '1 doesn\'t say where it was taken: place it on the route '
                'from the ride\'s journal once it\'s saved.'
            : '${result.unplaced} don\'t say where they were taken: place '
                'them on the route from the ride\'s journal once it\'s saved.',
      if (result.skipped > 0)
        '${result.skipped} skipped (photos and videos up to 50 MB: JPEG, '
            'PNG, HEIC, MP4, MOV).',
    ].join(' ');
    setState(() {
      _adding = false;
      _mediaNote = note.isEmpty ? null : note;
    });
  }

  void _say(String message) {
    if (!mounted || message.isEmpty) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final finished = ref.watch(finishedRideProvider);
    if (finished == null) return const SizedBox.shrink();
    return Column(
      children: [
        Expanded(
          // Not a ListView: the ride card must stay painted to be captured
          // even when it's scrolled out of view.
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(top: 16, bottom: 24),
            child: RiseIn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _padded(_header(finished)),
                  const SizedBox(height: 16),
                  _padded(_summary(finished)),
                  _section('Title', _titleField(finished)),
                  _section('About the ride', _storyField()),
                  _section('Motorcycle', _bikePicker(finished)),
                  _section(
                    'Photos & memories',
                    _mediaStrip(finished),
                    padded: false,
                  ),
                  if (_mediaNote != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Text(_mediaNote!,
                          style: monoStyle(size: 11, tracking: 0)),
                    ),
                  _section('Who can see this ride', _visibility(finished)),
                ],
              ),
            ),
          ),
        ),
        _actions(finished),
      ],
    );
  }

  static Widget _padded(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20), child: child);

  /// A labelled part of the form.
  Widget _section(String label, Widget child, {bool padded = true}) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _padded(LabelMono(label)),
          const SizedBox(height: 8),
          padded ? _padded(child) : child,
        ],
      ),
    );
  }

  Widget _header(FinishedRide finished) {
    final ride = finished.ride;
    final where = placesLine(ride.startPlace, ride.endPlace);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
                decoration: const BoxDecoration(
                    color: AppColors.accent, shape: BoxShape.circle),
                child: const PlantedFlag(size: 36, waving: true),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nice ride.', style: displayStyle(size: 32)),
                    if (where != null) ...[
                      const SizedBox(height: 4),
                      Text(where,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: monoStyle(size: 12, tracking: 0)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (finished.canResume)
          _ResumeBanner2(
              onResume: () =>
                  ref.read(rideRecorderProvider.notifier).resumeFinished()),
      ],
    );
  }

  Widget _summary(FinishedRide finished) {
    final ride = finished.ride;
    final flag = flagPoint(ride.points);
    final when = ride.startedAt?.toLocal();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TrackedRouteMap.track(
            ride.points,
            height: 200,
            pins: [
              if (flag != null && ride.points.length >= 2)
                flagMarker((lat: flag.lat, lng: flag.lng), size: 32),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StatBlock(
                          value: context.units.fixed(ride.distanceKm, 2),
                          label: context.units.distanceUnit,
                          valueSize: 30),
                    ),
                    Expanded(
                      child: StatBlock(
                          value: clock(ride.movingTimeSecs),
                          label: 'moving time',
                          valueSize: 30),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: StatBlock(
                          value: context.units.speedText(ride.maxSpeedKmh),
                          label: 'top speed',
                          valueSize: 30),
                    ),
                    Expanded(
                      child: StatBlock(
                          value: context.units.speedText(ride.avgSpeedKmh),
                          label: 'avg speed',
                          valueSize: 30),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (when != null || finished.elapsedSecs > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Text(
                [
                  if (when != null) formatRideDate(when),
                  if (finished.elapsedSecs > 0)
                    'elapsed ${clock(finished.elapsedSecs)}',
                ].join(' · '),
                style: monoStyle(size: 11, tracking: 0),
              ),
            ),
        ],
      ),
    );
  }

  static InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: AppColors.mutedForeground.withValues(alpha: 0.85),
            fontSize: 15,
            height: 1.4),
        filled: true,
        fillColor: AppColors.card,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        counterText: '',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      );

  Widget _titleField(FinishedRide finished) {
    return TextField(
      controller: _title,
      maxLength: 80,
      textCapitalization: TextCapitalization.sentences,
      inputFormatters: const [CapitalizeFirstFormatter()],
      textInputAction: TextInputAction.next,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      decoration: _input(finished.defaultTitle),
      onChanged: _finished.setTitle,
    );
  }

  Widget _storyField() {
    return TextField(
      controller: _story,
      minLines: 3,
      maxLines: 8,
      maxLength: 5000,
      textCapitalization: TextCapitalization.sentences,
      inputFormatters: const [CapitalizeFirstFormatter()],
      style: const TextStyle(fontSize: 15, height: 1.45),
      decoration: _input('What did you like about the ride? Anything you\'d '
          'like to share: the roads, the stops, the views, the people…'),
      onChanged: _finished.setJournal,
    );
  }

  /// The bike it's credited to: the one picked before START, unless changed
  /// here.
  Widget _bikePicker(FinishedRide finished) {
    final bikes = ref.watch(myBikesProvider).value ?? const <BikeRecord>[];
    final ride = finished.ride;
    final current = bikes.where((b) => b.id == ride.bikeId).firstOrNull;
    if (bikes.isEmpty || current == null && ride.bikeId != null) {
      // Not loaded (offline) or not one of theirs any more: as recorded.
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const _BikeThumb(null),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                ride.bikeName.isEmpty ? 'Your primary bike' : ride.bikeName,
                style: displayStyle(size: 16),
              ),
            ),
          ],
        ),
      );
    }
    return DropdownButtonFormField<String>(
      key: ValueKey(ride.bikeId),
      initialValue: current?.id,
      isExpanded: true,
      isDense: false,
      itemHeight: 60,
      borderRadius: BorderRadius.circular(14),
      dropdownColor: AppColors.card,
      icon: const Icon(Icons.expand_more, color: AppColors.mutedForeground),
      decoration: _input('Pick the bike you rode').copyWith(
          isDense: false,
          contentPadding: const EdgeInsets.fromLTRB(12, 4, 12, 4)),
      items: [
        for (final b in bikes)
          DropdownMenuItem(value: b.id, child: _BikeOption(b)),
      ],
      onChanged: (id) {
        final bike = bikes.where((b) => b.id == id).firstOrNull;
        if (bike != null) _finished.setBike(bike);
      },
    );
  }

  /// The ride card first (the bike's photo with the ride's stats), then
  /// adding photos, then the photos and videos added.
  Widget _mediaStrip(FinishedRide finished) {
    final media = finished.ride.media;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTile(finished),
          const SizedBox(width: 10),
          _MediaTile(
            label: _adding ? 'Adding…' : 'Add photos',
            child: _AddTile(busy: _adding, onTap: _addMedia),
          ),
          for (final m in media) ...[
            const SizedBox(width: 10),
            _MediaTile(
              key: ValueKey(m.id),
              label:
                  m.placed ? 'On the route' : (m.isVideo ? 'Video' : 'Photo'),
              onRemove: () => _finished.removeMedia(m),
              child: _LocalMediaThumb(localId: finished.ride.localId, media: m),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardTile(FinishedRide finished) {
    final attach = finished.attachCard;
    return ValueListenableBuilder<ShareCardDesign>(
      valueListenable: _card,
      builder: (context, design, _) => _MediaTile(
        label: 'Ride card',
        badge: Semantics(
          button: true,
          toggled: attach,
          label: attach ? 'Ride card posted with the ride' : 'Post ride card',
          child: GestureDetector(
            onTap: () => _setAttachCard(!attach),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: attach
                    ? AppColors.primary
                    : Colors.white.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                border: Border.all(
                    color: attach ? Colors.white : AppColors.border, width: 2),
              ),
              child: Icon(attach ? Icons.check : Icons.add,
                  size: 15,
                  color: attach ? Colors.white : AppColors.mutedForeground),
            ),
          ),
        ),
        child: Semantics(
          button: true,
          label: 'Edit ride card',
          child: GestureDetector(
            onTap: _openShare,
            child: AnimatedOpacity(
              opacity: attach ? 1 : 0.45,
              duration: const Duration(milliseconds: 200),
              child: ShareCardFrame(
                  boundaryKey: _cardKey, item: finished.item, design: design),
            ),
          ),
        ),
      ),
    );
  }

  Widget _visibility(FinishedRide finished) {
    return IgnorePointer(
      ignoring: finished.saving,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VisibilityPicker(
            value: finished.visibility,
            onChanged: _finished.setVisibility,
          ),
          const SizedBox(height: 8),
          Text(visibilityAudience(finished.visibility),
              style: const TextStyle(
                  fontSize: 13, color: AppColors.mutedForeground)),
        ],
      ),
    );
  }

  /// Saving by itself, as the bottom bar says; then DISCARD or DONE.
  Widget _actions(FinishedRide finished) {
    final saved = finished.saved;
    final saving = finished.saving;
    final saveError = finished.saveError;
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    // A short ride (an accidental START/FINISH) isn't saved by itself.
    final manual = saved == null && !saving && saveError == null;

    final (IconData icon, Color color, String status) = saveError != null
        ? (Icons.error_outline, Colors.redAccent, saveError)
        : saving
            ? (
                Icons.cloud_upload_outlined,
                AppColors.mutedForeground,
                'Saving your ride…'
              )
            : saved == null
                ? (
                    Icons.info_outline,
                    AppColors.mutedForeground,
                    'Too short to save by itself.'
                  )
                : saved.synced
                    ? (
                        Icons.check_circle,
                        AppColors.primary,
                        'Saved to your profile. Changes save as you go.'
                      )
                    : (
                        Icons.cloud_off_outlined,
                        AppColors.mutedForeground,
                        'Saved on this phone. It uploads when you\'re online.'
                      );

    Widget label(String text) => FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(text, maxLines: 1, style: displayStyle(size: 18)),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(status,
                      style: TextStyle(
                          fontSize: 13,
                          color: saveError != null
                              ? Colors.redAccent
                              : AppColors.mutedForeground)),
                ),
              ],
            ),
          ),
          Row(
            children: [
              SizedBox(
                height: 56,
                width: 56,
                child: OutlinedButton(
                  onPressed: _openShare,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.foreground,
                    side: const BorderSide(color: AppColors.border),
                    padding: EdgeInsets.zero,
                    shape: shape,
                  ),
                  child: const Icon(Icons.ios_share,
                      size: 20, semanticLabel: 'Share'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton(
                    onPressed: saving ? null : _delete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFC92A2A),
                      side: const BorderSide(color: AppColors.border),
                      shape: shape,
                    ),
                    child: DefaultTextStyle.merge(
                      style: const TextStyle(color: Color(0xFFC92A2A)),
                      child: label('DISCARD'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: saveError != null || manual
                        ? () {
                            hideKeyboard();
                            _finished.save();
                            _celebrate();
                          }
                        : () {
                            hideKeyboard();
                            _finished.close();
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: shape,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                          saveError != null
                              ? 'TRY AGAIN'
                              : manual
                                  ? 'SAVE RIDE'
                                  : 'DONE',
                          maxLines: 1,
                          style: displayStyle(
                              size: 18, color: AppColors.primaryForeground)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// RESUME, next to the header: carries on recording the same ride.
class _ResumeBanner2 extends StatelessWidget {
  const _ResumeBanner2({required this.onResume});

  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.55),
        ),
      ),
      child: FilledButton.icon(
        onPressed: onResume,
        icon:
            Icon(Icons.play_arrow_rounded, size: 18, color: AppColors.primary),
        label: Text(
          'RESUME',
          style: displayStyle(size: 15, color: AppColors.primary),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: const StadiumBorder(),
          elevation: 0,
        ),
      ),
    );
  }
}

/// One tile in the photos row: 4:5, with a label under it and an optional
/// corner control.
class _MediaTile extends StatelessWidget {
  const _MediaTile({
    super.key,
    required this.label,
    required this.child,
    this.badge,
    this.onRemove,
  });

  static const width = 112.0;
  static const height = 140.0;

  final String label;
  final Widget child;
  final Widget? badge;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: child,
                  ),
                ),
                if (badge != null) Positioned(top: 6, right: 6, child: badge!),
                if (onRemove != null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Semantics(
                      button: true,
                      label: 'Remove',
                      child: GestureDetector(
                        onTap: onRemove,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close,
                              size: 15, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(size: 11, tracking: 0)),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: CustomPaint(
          painter: const DashedRRectPainter(radius: 12),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined,
                          size: 28, color: AppColors.primary),
                      SizedBox(height: 6),
                      Text('Photos &\nvideos',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.25,
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

/// A photo (or video) added to the ride, from the copy kept on the phone.
class _LocalMediaThumb extends ConsumerStatefulWidget {
  const _LocalMediaThumb({required this.localId, required this.media});

  final String localId;
  final PendingMedia media;

  @override
  ConsumerState<_LocalMediaThumb> createState() => _LocalMediaThumbState();
}

class _LocalMediaThumbState extends ConsumerState<_LocalMediaThumb> {
  late final Future<Uint8List?> _bytes = widget.media.isVideo
      ? Future.value(null)
      : ref
          .read(localRideStoreProvider)
          .loadMedia(widget.localId, widget.media);

  @override
  Widget build(BuildContext context) {
    if (widget.media.isVideo) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2B2D33), Color(0xFF14151A)],
          ),
        ),
        child: Center(
          child: Icon(Icons.play_circle_fill_rounded,
              size: 36, color: Colors.white70),
        ),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return snapshot.connectionState == ConnectionState.done
              ? const ColoredBox(color: AppColors.panel)
              : const Shimmer(
                  child: SkeletonBox(height: double.infinity, radius: 0));
        }
        return Image.memory(bytes,
            fit: BoxFit.cover,
            cacheWidth: 360,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: AppColors.panel));
      },
    );
  }
}

class _BikeOption extends StatelessWidget {
  const _BikeOption(this.bike);

  final BikeRecord bike;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _BikeThumb(bike.photoUrl),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(bike.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: displayStyle(size: 16)),
              const SizedBox(height: 2),
              Text(
                [
                  '${context.units.totalText(bike.riddenKm)} ridden',
                  if (bike.isPrimary) 'Primary',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(size: 11, tracking: 0),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BikeThumb extends StatelessWidget {
  const _BikeThumb(this.url);

  final String? url;

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: AppColors.panel,
      child: Center(
        child:
            Icon(Icons.two_wheeler, size: 20, color: AppColors.mutedForeground),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 36,
        child: url == null
            ? placeholder
            : NetworkPhoto(url!, fallback: placeholder),
      ),
    );
  }
}
