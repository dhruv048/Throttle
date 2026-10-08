import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

class BikeRepository {
  BikeRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const photoBucket = 'bike-photos';

  Future<List<BikeRecord>> listForUser(String userId) async {
    final rows = await _client
        .from('bikes')
        .select()
        .eq('user_id', userId)
        .order('is_primary', ascending: false)
        .order('created_at');
    return (rows as List)
        .map((e) => BikeRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<BikeRecord> create({
    required String userId,
    required String name,
    String? make,
    String? model,
    int? year,
    double odometerKm = 0,
    bool isPrimary = false,
  }) async {
    final row = await _client
        .from('bikes')
        .insert({
          'user_id': userId,
          'name': name,
          'make': make,
          'model': model,
          'year': year,
          'odometer_km': odometerKm,
          'is_primary': isPrimary,
        })
        .select()
        .single();
    return BikeRecord.fromJson(Map<String, dynamic>.from(row));
  }

  /// Updates the given fields. Pass [clearPhoto] to remove the photo URL.
  Future<BikeRecord> update(
    String id, {
    String? name,
    String? make,
    String? model,
    int? year,
    bool? isPrimary,
    String? photoUrl,
    bool clearPhoto = false,
  }) async {
    final row = await _client
        .from('bikes')
        .update({
          if (name != null) 'name': name,
          if (make != null) 'make': make,
          if (model != null) 'model': model,
          if (year != null) 'year': year,
          if (isPrimary != null) 'is_primary': isPrimary,
          if (photoUrl != null) 'photo_url': photoUrl,
          if (clearPhoto) 'photo_url': null,
        })
        .eq('id', id)
        .select()
        .single();
    return BikeRecord.fromJson(Map<String, dynamic>.from(row));
  }

  /// Uploads a photo for [bike] and points the bike at it. Each upload gets a
  /// new file name so CDN/image caches never show the old photo; the previous
  /// file is removed best-effort.
  Future<BikeRecord> setPhoto(BikeRecord bike, XFile photo) async {
    final bytes = await photo.readAsBytes();
    final ext = _extension(photo);
    final path =
        '${bike.userId}/${bike.id}-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from(photoBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
            cacheControl: '31536000',
          ),
        );
    final url = _client.storage.from(photoBucket).getPublicUrl(path);
    final updated = await update(bike.id, photoUrl: url);
    await _removeStoredPhoto(bike.photoUrl);
    return updated;
  }

  Future<BikeRecord> removePhoto(BikeRecord bike) async {
    final updated = await update(bike.id, clearPhoto: true);
    await _removeStoredPhoto(bike.photoUrl);
    return updated;
  }

  Future<void> _removeStoredPhoto(String? url) async {
    if (url == null) return;
    final marker = '/$photoBucket/';
    final i = url.indexOf(marker);
    if (i < 0) return;
    try {
      await _client.storage
          .from(photoBucket)
          .remove([url.substring(i + marker.length)]);
    } catch (_) {
      // An orphaned file is harmless; don't fail the edit over it.
    }
  }

  static String _extension(XFile f) {
    final name = f.name.toLowerCase();
    return name.endsWith('.png') ? 'png' : 'jpg';
  }

  Future<BikeRecord?> findByName(String userId, String name) async {
    final row = await _client
        .from('bikes')
        .select()
        .eq('user_id', userId)
        .eq('name', name)
        .maybeSingle();
    if (row == null) return null;
    return BikeRecord.fromJson(Map<String, dynamic>.from(row));
  }
}
