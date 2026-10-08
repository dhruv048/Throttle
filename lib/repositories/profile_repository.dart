import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

class ProfileRepository {
  ProfileRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

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
}
