import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import 'core.dart';
import 'live.dart';
import 'rider.dart';

/// A ride's journal as loaded: the rider's words and the photos and videos.
@immutable
class RideJournal {
  const RideJournal({this.text, this.media = const []});

  final String? text;
  final List<RideMedia> media;

  bool get isEmpty => (text?.trim().isEmpty ?? true) && media.isEmpty;

  RideJournal withText(String? text) => RideJournal(text: text, media: media);

  RideJournal withMedia(List<RideMedia> media) =>
      RideJournal(text: text, media: media);
}

/// A ride's journal, by ride id. Changes made through it show everywhere the
/// ride is open (its page and its journal).
final rideJournalProvider = AsyncNotifierProvider.autoDispose
    .family<RideJournalNotifier, RideJournal, String>(RideJournalNotifier.new);

class RideJournalNotifier extends AsyncNotifier<RideJournal> {
  RideJournalNotifier(this.rideId);

  final String rideId;

  @override
  Future<RideJournal> build() async {
    ref.watch(currentUserIdProvider);
    // Photos saved with the ride can finish uploading after it opens.
    ref.watch(mediaRevisionProvider);
    final repo = ref.watch(journalRepositoryProvider);
    final (text, media) = await (repo.journal(rideId), repo.media(rideId)).wait;
    return RideJournal(text: text, media: media);
  }

  RideJournal get _current => state.value ?? const RideJournal();

  Future<void> setText(String text) async {
    final saved =
        await ref.read(journalRepositoryProvider).setJournal(rideId, text);
    if (ref.mounted) state = AsyncData(_current.withText(saved));
  }

  Future<RideMedia> add({
    required Uint8List bytes,
    required String extension,
    double? lat,
    double? lng,
    DateTime? takenAt,
  }) async {
    final media = await ref.read(journalRepositoryProvider).addMedia(
          rideId: rideId,
          bytes: bytes,
          extension: extension,
          lat: lat,
          lng: lng,
          takenAt: takenAt,
        );
    if (ref.mounted) {
      state = AsyncData(_current.withMedia([..._current.media, media]));
    }
    _memoriesChanged(media.userId);
    return media;
  }

  /// The rider's memories (every ride's photos) include this ride's.
  void _memoriesChanged(String userId) {
    if (ref.mounted) ref.invalidate(riderMemoriesProvider(userId));
  }

  Future<void> edit(RideMedia media,
      {String? caption, double? lat, double? lng}) async {
    final updated = await ref
        .read(journalRepositoryProvider)
        .update(media, caption: caption, lat: lat, lng: lng);
    if (ref.mounted) {
      state = AsyncData(_current.withMedia([
        for (final m in _current.media) m.id == media.id ? updated : m,
      ]));
    }
  }

  Future<void> remove(RideMedia media) async {
    await ref.read(journalRepositoryProvider).delete(media);
    if (ref.mounted) {
      state = AsyncData(_current.withMedia([
        for (final m in _current.media)
          if (m.id != media.id) m
      ]));
    }
    _memoriesChanged(media.userId);
  }
}

/// Picks photos and videos for a journal (tests swap in their own files).
final pickJournalMediaProvider = Provider<Future<List<XFile>> Function()>(
  (ref) => () => ImagePicker().pickMultipleMedia(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
        limit: 20,
      ),
);
