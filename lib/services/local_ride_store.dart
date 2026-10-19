import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

class LocalRideStore {
  static const _fileName = 'pending_rides.json';
  static const _draftName = 'ride_draft.json';
  static const _liveName = 'ride_in_progress.json';
  static const _cardsDir = 'ride_cards';
  static const _mediaDir = 'ride_media';

  // Every mutation is read-modify-write on one file; chain them so a save
  // and a background sync can't overwrite each other's changes.
  static Future<void> _tail = Future.value();
  static int _inFlight = 0;

  static Future<T> _serialized<T>(Future<T> Function() op) {
    // Only wait behind work that is still running.
    final result = _inFlight == 0 ? op() : _tail.then((_) => op());
    _inFlight++;
    _tail =
        result.then((_) {}, onError: (_) {}).whenComplete(() => _inFlight--);
    return result;
  }

  /// Tests: keep the queue in memory instead of a file (widget tests run on
  /// a simulated clock and can't wait on real file IO). While it's set, the
  /// draft and ride cards are kept in [debugDraft] and [debugCards].
  @visibleForTesting
  static String? debugMemory;
  @visibleForTesting
  static String? debugDraft;
  @visibleForTesting
  static final debugCards = <String, Uint8List>{};
  @visibleForTesting
  static String? debugLive;

  /// Tests: photos and videos waiting with their ride, by
  /// `<local id>/<file name>`.
  @visibleForTesting
  static final debugMedia = <String, Uint8List>{};

  /// Tests: an empty in-memory store, with nothing left over from the last
  /// test (whose simulated clock has stopped).
  @visibleForTesting
  static void debugReset() {
    debugMemory = '[]';
    debugDraft = null;
    debugCards.clear();
    debugLive = null;
    debugMedia.clear();
    _tail = Future.value();
    _inFlight = 0;
  }

  Future<Directory> _dir() => getApplicationDocumentsDirectory();

  Future<File> _file() async => File('${(await _dir()).path}/$_fileName');

  Future<List<PendingRide>> loadAll() async {
    try {
      final String raw;
      if (debugMemory != null) {
        raw = debugMemory!;
      } else {
        final file = await _file();
        if (!await file.exists()) return [];
        raw = await file.readAsString();
      }
      if (raw.trim().isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => PendingRide.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Uploaded rides are kept only while something of theirs (photos, the
  /// ride card) is still to go up, or for a couple of weeks, and then
  /// without their track: the server has it. Every save and sync rewrites
  /// this file, so it must stay small.
  static const keepUploadedFor = Duration(days: 14);

  Future<void> saveAll(List<PendingRide> rides) async {
    final now = DateTime.now();
    final kept = [
      for (final r in rides)
        if (!r.synced)
          r
        else if (_uploadsLeft(r) ||
            now.difference(r.createdAt) < keepUploadedFor)
          r.points.isEmpty ? r : r.copyWith(points: const [])
    ];
    final encoded = jsonEncode(kept.map((r) => r.toJson()).toList());
    if (debugMemory != null) {
      debugMemory = encoded;
      return;
    }
    final file = await _file();
    await file.writeAsString(encoded, flush: true);
  }

  /// Adds [ride] to the front of the queue, replacing an earlier copy.
  Future<PendingRide> enqueue(PendingRide ride) => _serialized(() async {
        final all = await loadAll();
        all.removeWhere((r) => r.localId == ride.localId);
        all.insert(0, ride);
        await saveAll(all);
        return ride;
      });

  /// The ride (and track) is uploaded. Its ride card and photos follow
  /// (see [markCardUploaded], [markMediaUploaded]).
  Future<void> markSynced(String localId, String remoteId) =>
      _serialized(() async {
        final all = await loadAll();
        for (final r in all) {
          if (r.localId == localId) {
            r.synced = true;
            r.remoteId = remoteId;
          }
        }
        await saveAll(all);
      });

  /// The ride card is uploaded to [url]: the phone's copy goes.
  Future<void> markCardUploaded(String localId, String? url) =>
      _serialized(() async {
        final all = await loadAll();
        for (final r in all) {
          if (r.localId == localId) r.cardImageUrl = url;
        }
        await saveAll(all);
        await _deleteCard(localId);
      });

  /// An uploaded ride with photos, videos or its ride card still to go up.
  static bool _uploadsLeft(PendingRide r) =>
      r.media.any((m) => !m.uploaded) || (r.hasCard && r.cardImageUrl == null);

  /// Uploaded rides with photos, videos or a ride card still to go up.
  Future<List<PendingRide>> withUploadsLeft() async {
    final all = await loadAll();
    return all
        .where((r) => r.synced && r.remoteId != null && _uploadsLeft(r))
        .toList();
  }

  /// The ride saved here as [localId], if it still is.
  Future<PendingRide?> find(String localId) async =>
      (await loadAll()).where((r) => r.localId == localId).firstOrNull;

  /// Changes the ride saved here as [localId] (if it still is), and returns
  /// it as now stored.
  Future<PendingRide?> update(
          String localId, PendingRide Function(PendingRide ride) change) =>
      _serialized(() async {
        final all = await loadAll();
        final i = all.indexWhere((r) => r.localId == localId);
        if (i < 0) return null;
        all[i] = change(all[i]);
        await saveAll(all);
        return all[i];
      });

  /// One of a ride's photos or videos made it into its journal: it isn't
  /// uploaded again, and the phone's copy goes.
  Future<void> markMediaUploaded(String localId, PendingMedia media) =>
      _serialized(() async {
        final all = await loadAll();
        final i = all.indexWhere((r) => r.localId == localId);
        if (i >= 0) {
          all[i] = all[i].copyWith(media: [
            for (final m in all[i].media)
              m.id == media.id ? m.markUploaded() : m,
          ]);
          await saveAll(all);
        }
        await deleteMedia(localId, media);
      });

  /// Changes who can see a ride saved here; if it hasn't uploaded yet, it
  /// uploads that way. Returns the ride as now stored, or null if it isn't.
  Future<PendingRide?> setVisibility(
          String localId, RideVisibility visibility) =>
      _serialized(() async {
        final all = await loadAll();
        final i = all.indexWhere((r) => r.localId == localId);
        if (i < 0) return null;
        all[i] = all[i].copyWith(visibility: visibility);
        await saveAll(all);
        return all[i];
      });

  Future<List<PendingRide>> pendingUnsynced() async {
    final all = await loadAll();
    return all.where((r) => !r.synced).toList();
  }

  Future<void> remove(String localId) => _serialized(() async {
        final all = await loadAll();
        all.removeWhere((r) => r.localId == localId);
        await saveAll(all);
        await _deleteCard(localId);
        await deleteAllMedia(localId);
      });

  // ---------------------------------------------------------------------------
  // Draft: a finished ride the rider hasn't saved or discarded yet. Kept so
  // closing the app on the post-ride screen doesn't lose it. Never uploaded.
  // ---------------------------------------------------------------------------

  Future<PendingRide?> loadDraft() async => (await loadDraftWithResume())?.ride;

  /// The draft, with the recording as it was at FINISH (see [saveDraft]).
  Future<({PendingRide ride, Map<String, dynamic>? resume})?>
      loadDraftWithResume() async {
    try {
      final String? raw;
      if (debugMemory != null) {
        raw = debugDraft;
      } else {
        final file = File('${(await _dir()).path}/$_draftName');
        raw = await file.exists() ? await file.readAsString() : null;
      }
      if (raw == null || raw.trim().isEmpty) return null;
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final resume = json['resume'];
      return (
        ride: PendingRide.fromJson(json),
        resume: resume is Map ? Map<String, dynamic>.from(resume) : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// [resume] is the recording as it was at FINISH, so a ride finished by
  /// mistake can carry on even after the app restarts.
  Future<void> saveDraft(PendingRide ride, {Map<String, dynamic>? resume}) =>
      _serialized(() async {
        final encoded = jsonEncode({
          ...ride.toJson(),
          if (resume != null) 'resume': resume,
        });
        if (debugMemory != null) {
          debugDraft = encoded;
          return;
        }
        await File('${(await _dir()).path}/$_draftName')
            .writeAsString(encoded, flush: true);
      });

  Future<void> clearDraft() => _serialized(() async {
        if (debugMemory != null) {
          debugDraft = null;
          return;
        }
        final file = File('${(await _dir()).path}/$_draftName');
        if (await file.exists()) await file.delete();
      });

  // ---------------------------------------------------------------------------
  // The ride being recorded, saved every few seconds so it survives the app
  // being closed (or killed by the system) mid-ride. Never uploaded.
  // ---------------------------------------------------------------------------

  // Each write goes to a temporary file that then replaces the last, so a
  // kill mid-write leaves the previous copy intact.
  Future<void> saveLive(Map<String, dynamic> ride) {
    final encoded = jsonEncode(ride);
    return _serialized(() async {
      if (debugMemory != null) {
        debugLive = encoded;
        return;
      }
      final dir = (await _dir()).path;
      final tmp = File('$dir/$_liveName.tmp');
      await tmp.writeAsString(encoded, flush: true);
      await tmp.rename('$dir/$_liveName');
    }).catchError((Object e) => debugPrint('Couldn\'t keep the ride: $e'));
  }

  Future<Map<String, dynamic>?> loadLive() async {
    try {
      final String? raw;
      if (debugMemory != null) {
        raw = debugLive;
      } else {
        final file = File('${(await _dir()).path}/$_liveName');
        raw = await file.exists() ? await file.readAsString() : null;
      }
      if (raw == null || raw.trim().isEmpty) return null;
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearLive() => _serialized(() async {
        if (debugMemory != null) {
          debugLive = null;
          return;
        }
        final file = File('${(await _dir()).path}/$_liveName');
        if (await file.exists()) await file.delete();
      }).catchError((Object e) => debugPrint('Couldn\'t clear the ride: $e'));

  // ---------------------------------------------------------------------------
  // Ride card images (JPEG) waiting to upload with their ride.
  // ---------------------------------------------------------------------------

  Future<File> _cardFile(String localId) async =>
      File('${(await _dir()).path}/$_cardsDir/$localId.jpg');

  Future<void> saveCard(String localId, Uint8List jpeg) async {
    if (debugMemory != null) {
      debugCards[localId] = jpeg;
      return;
    }
    final file = await _cardFile(localId);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(jpeg, flush: true);
  }

  Future<Uint8List?> loadCard(String localId) async {
    if (debugMemory != null) return debugCards[localId];
    try {
      final file = await _cardFile(localId);
      return await file.exists() ? await file.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteCard(String localId) => _deleteCard(localId);

  Future<void> _deleteCard(String localId) async {
    if (debugMemory != null) {
      debugCards.remove(localId);
      return;
    }
    try {
      final file = await _cardFile(localId);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A leftover image is harmless.
    }
  }
  // ---------------------------------------------------------------------------
  // Photos and videos added to a ride before it uploaded: kept here, by the
  // ride's local id, until they're in its journal.
  // ---------------------------------------------------------------------------

  Future<Directory> _mediaFolder(String localId) async =>
      Directory('${(await _dir()).path}/$_mediaDir/$localId');

  Future<void> saveMedia(
      String localId, PendingMedia media, Uint8List bytes) async {
    if (debugMemory != null) {
      debugMedia['$localId/${media.fileName}'] = bytes;
      return;
    }
    final folder = await _mediaFolder(localId);
    await folder.create(recursive: true);
    await File('${folder.path}/${media.fileName}')
        .writeAsBytes(bytes, flush: true);
  }

  Future<Uint8List?> loadMedia(String localId, PendingMedia media) async {
    if (debugMemory != null) return debugMedia['$localId/${media.fileName}'];
    try {
      final file =
          File('${(await _mediaFolder(localId)).path}/${media.fileName}');
      return await file.exists() ? await file.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteMedia(String localId, PendingMedia media) async {
    if (debugMemory != null) {
      debugMedia.remove('$localId/${media.fileName}');
      return;
    }
    try {
      final file =
          File('${(await _mediaFolder(localId)).path}/${media.fileName}');
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A leftover file is harmless.
    }
  }

  /// Everything kept for the ride [localId] (discarded, deleted or synced).
  Future<void> deleteAllMedia(String localId) async {
    if (debugMemory != null) {
      debugMedia.removeWhere((key, _) => key.startsWith('$localId/'));
      return;
    }
    try {
      final folder = await _mediaFolder(localId);
      if (await folder.exists()) await folder.delete(recursive: true);
    } catch (_) {
      // Leftover files are harmless.
    }
  }
}
