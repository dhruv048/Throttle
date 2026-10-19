import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../services/data_changes.dart';

class ProfileRepository {
  ProfileRepository({
    SupabaseClient? client,
    DataChanges changes = const DataChanges(),
  })  : _client = client ?? Supabase.instance.client,
        _changes = changes;

  final SupabaseClient _client;
  final DataChanges _changes;

  Future<Profile?> getById(String id) async {
    final row =
        await _client.from('profiles').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    return Profile.fromJson(Map<String, dynamic>.from(row));
  }

  Future<Profile?> getByUsername(String username) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('username', username.toLowerCase())
        .maybeSingle();
    if (row == null) return null;
    return Profile.fromJson(Map<String, dynamic>.from(row));
  }

  Future<bool> isUsernameAvailable(String username,
      {String? excludingUserId}) async {
    final q = _client
        .from('profiles')
        .select('id')
        .eq('username', username.toLowerCase());
    final row = await q.maybeSingle();
    if (row == null) return true;
    if (excludingUserId != null && row['id'] == excludingUserId) return true;
    return false;
  }

  Future<Profile> update(
    String id, {
    String? username,
    String? displayName,
    String? city,
    String? bio,
    String? avatarUrl,
    bool? onboardingCompleted,
  }) async {
    final payload = <String, dynamic>{};
    if (username != null) payload['username'] = username.toLowerCase();
    if (displayName != null) payload['display_name'] = displayName;
    if (city != null) payload['city'] = city;
    if (bio != null) payload['bio'] = bio;
    if (avatarUrl != null) payload['avatar_url'] = avatarUrl;
    if (onboardingCompleted != null) {
      payload['onboarding_completed'] = onboardingCompleted;
    }

    final row = await _client
        .from('profiles')
        .update(payload)
        .eq('id', id)
        .select()
        .single();
    return Profile.fromJson(Map<String, dynamic>.from(row));
  }

  Future<({int followers, int following})> followCounts(String id) async {
    final results = await Future.wait([
      _client.from('follows').count(CountOption.exact).eq('following_id', id),
      _client.from('follows').count(CountOption.exact).eq('follower_id', id),
    ]);
    return (followers: results[0], following: results[1]);
  }

  /// Riders matching [query] by username or name (all riders when empty),
  /// newest first, excluding [excludeId].
  Future<List<Profile>> search(String query,
      {String? excludeId, int limit = 30}) async {
    var q = _client.from('profiles').select().eq('onboarding_completed', true);
    final term = query.trim().replaceAll(RegExp(r'[%,()*]'), '');
    if (term.isNotEmpty) {
      q = q.or('username.ilike.%$term%,display_name.ilike.%$term%');
    }
    if (excludeId != null) q = q.neq('id', excludeId);
    final rows =
        await q.order('created_at', ascending: false).limit(limit) as List;
    return rows
        .map((e) => Profile.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Ids of the riders [userId] follows.
  Future<Set<String>> followingIds(String userId) async {
    final rows = await _client
        .from('follows')
        .select('following_id')
        .eq('follower_id', userId) as List;
    return rows.map((r) => r['following_id'] as String).toSet();
  }

  Future<void> follow(String followerId, String followingId) async {
    await _client.from('follows').upsert(
      {'follower_id': followerId, 'following_id': followingId},
      onConflict: 'follower_id,following_id',
      ignoreDuplicates: true,
    );
    _changes.follows();
  }

  Future<void> unfollow(String followerId, String followingId) async {
    await _client
        .from('follows')
        .delete()
        .eq('follower_id', followerId)
        .eq('following_id', followingId);
    _changes.follows();
  }
}
