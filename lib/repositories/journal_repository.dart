import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/db_log.dart';

/// A ride's journal: the rider's words about it, and photos and videos
/// pinned along its route. Only for rides that have uploaded.
class JournalRepository {
  JournalRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Public bucket, one folder per rider, then per ride.
  static const bucket = 'ride-media';

  /// The bucket's limit.
  static const maxBytes = 50 * 1024 * 1024;

  static const _types = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'heic': 'image/heic',
    'webp': 'image/webp',
    'mp4': 'video/mp4',
    'm4v': 'video/mp4',
    'mov': 'video/quicktime',
  };

  /// The content type for a file with [extension], or null if it can't go
  /// in a journal.
  static String? contentType(String extension) =>
      _types[extension.toLowerCase()];

  static bool isVideo(String extension) =>
      contentType(extension)?.startsWith('video/') ?? false;

  /// The extension to store a picked file with ([name], else [mimeType]),
  /// or null if it isn't a kind a journal takes.
  static String? extensionFor(String name, String? mimeType) {
    final dot = name.lastIndexOf('.');
    var ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    if (contentType(ext) == null && mimeType != null) {
      ext = switch (mimeType) {
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/heic' => 'heic',
        'video/mp4' => 'mp4',
        'video/quicktime' => 'mov',
        _ => ext,
      };
    }
    return contentType(ext) == null ? null : ext;
  }

  Future<String?> journal(String rideId) async {
    final row = await _client
        .from('rides')
        .select('journal')
        .eq('id', rideId)
        .maybeSingle();
    return row?['journal'] as String?;
  }

  /// Saves what the rider wrote; blank clears it.
  Future<String?> setJournal(String rideId, String text) async {
    final value = text.trim().isEmpty ? null : text.trim();
    await _client.from('rides').update({'journal': value}).eq('id', rideId);
    return value;
  }

  /// In the order they were taken (then added).
  Future<List<RideMedia>> media(String rideId) async {
    final rows = await _client
        .from('ride_media')
        .select()
        .eq('ride_id', rideId)
        .order('taken_at', nullsFirst: false)
        .order('created_at') as List;
    return rows
        .map((e) => RideMedia.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// A rider's photos and videos from every ride this rider may see,
  /// newest first, a page at a time, each with its ride's title.
  Future<List<RideMedia>> riderMedia(String userId,
      {int offset = 0, int limit = 60}) async {
    final rows = await _client
        .from('ride_media')
        .select('*, ride:rides(id, title)')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1) as List;
    return rows
        .map((e) => RideMedia.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Uploads a photo or video and adds it to the ride's journal at
  /// [lat]/[lng] (null: not on the route yet).
  ///
  /// [name] names its file, for one queued on the phone: a retry of an
  /// upload that may have got through finds it instead of adding it twice.
  Future<RideMedia> addMedia({
    required String rideId,
    required Uint8List bytes,
    required String extension,
    double? lat,
    double? lng,
    DateTime? takenAt,
    String? caption,
    String? name,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Not signed in');
    final ext = extension.toLowerCase();
    final type = contentType(ext);
    if (type == null) throw ArgumentError('Unsupported file type: .$ext');
    final path = '$uid/$rideId/${name ?? const Uuid().v4()}.$ext';
    if (name != null) {
      final existing = await _client
          .from('ride_media')
          .select()
          .eq('storage_path', path)
          .maybeSingle();
      if (existing != null) {
        return RideMedia.fromJson(Map<String, dynamic>.from(existing));
      }
    }
    final files = _client.storage.from(bucket);
    logStorageUpload(bucket, path, bytes, type);
    await files.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        contentType: type,
        cacheControl: '31536000',
        upsert: name != null, // a retry after a lost response must not fail
      ),
    );
    try {
      final mediaRow = {
        'ride_id': rideId,
        'user_id': uid,
        'kind': isVideo(ext) ? 'video' : 'photo',
        'url': files.getPublicUrl(path),
        'storage_path': path,
        'caption': caption,
        'lat': lat,
        'lng': lng,
        'taken_at': takenAt?.toUtc().toIso8601String(),
      };
      logDbWrite('ride_media INSERT', mediaRow);
      final row =
          await _client.from('ride_media').insert(mediaRow).select().single();
      return RideMedia.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      // Another upload of the same queued file got there first.
      if (name != null && e.code == '23505') {
        final existing = await _client
            .from('ride_media')
            .select()
            .eq('storage_path', path)
            .single();
        return RideMedia.fromJson(Map<String, dynamic>.from(existing));
      }
      await _removeFiles([path]);
      rethrow;
    } catch (_) {
      await _removeFiles([path]);
      rethrow;
    }
  }

  /// Changes its caption (blank removes it) and/or where it is on the route.
  Future<RideMedia> update(RideMedia media,
      {String? caption, double? lat, double? lng}) async {
    final changes = <String, dynamic>{
      if (caption != null) 'caption': caption.trim().isEmpty ? null : caption,
      if (lat != null && lng != null) ...{'lat': lat, 'lng': lng},
    };
    if (changes.isEmpty) return media;
    await _client.from('ride_media').update(changes).eq('id', media.id);
    return RideMedia(
      id: media.id,
      rideId: media.rideId,
      userId: media.userId,
      kind: media.kind,
      url: media.url,
      storagePath: media.storagePath,
      caption: changes.containsKey('caption')
          ? changes['caption'] as String?
          : media.caption,
      lat: lat ?? media.lat,
      lng: lng ?? media.lng,
      takenAt: media.takenAt,
      createdAt: media.createdAt,
    );
  }

  /// Takes the file at [storagePath] (in [bucket]) out of its journal.
  Future<void> deleteByPath(String storagePath) async {
    await _client.from('ride_media').delete().eq('storage_path', storagePath);
    await _removeFiles([storagePath]);
  }

  Future<void> delete(RideMedia media) async {
    await _client.from('ride_media').delete().eq('id', media.id);
    await _removeFiles([media.storagePath]);
  }

  /// A deleted ride's files (its rows go with the ride).
  Future<void> removeAllFor(String rideId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final files =
          await _client.storage.from(bucket).list(path: '$uid/$rideId');
      await _removeFiles([for (final f in files) '$uid/$rideId/${f.name}']);
    } catch (e) {
      debugPrint('Couldn\'t remove the ride\'s journal files: $e');
    }
  }

  Future<void> _removeFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _client.storage.from(bucket).remove(paths);
    } catch (_) {
      // An orphaned file is harmless.
    }
  }
}
