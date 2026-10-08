import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/models.dart';
import '../repositories/bike_repository.dart';
import '../repositories/profile_repository.dart';

class AuthService {
  AuthService({
    SupabaseClient? client,
    ProfileRepository? profiles,
    BikeRepository? bikes,
  })  : _client = client ?? Supabase.instance.client,
        _profiles = profiles ?? ProfileRepository(),
        _bikes = bikes ?? BikeRepository();

  final SupabaseClient _client;
  final ProfileRepository _profiles;
  final BikeRepository _bikes;
  final GoogleSignIn _google = GoogleSignIn.instance;
  bool _googleReady = false;

  SupabaseClient get client => _client;
  User? get currentUser => _client.auth.currentUser;
  Session? get session => _client.auth.currentSession;
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<void> ensureGoogleInitialized() async {
    if (_googleReady) return;
    await _google.initialize(
      clientId: SupabaseConfig.googleIosClientId.isEmpty
          ? null
          : SupabaseConfig.googleIosClientId,
      serverClientId: SupabaseConfig.googleWebClientId.isEmpty
          ? null
          : SupabaseConfig.googleWebClientId,
    );
    _googleReady = true;
  }

  Future<AuthResponse> signInWithGoogle() async {
    await ensureGoogleInitialized();

    if (SupabaseConfig.googleWebClientId.isEmpty) {
      // Browser OAuth fallback when native client IDs are not configured yet.
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : SupabaseConfig.authRedirect,
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
      return AuthResponse(session: _client.auth.currentSession);
    }

    try {
      final account = await _google.authenticate();
      final googleAuth = account.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw const AuthException('No ID token from Google Sign-In');
      }

      final authorization =
          await account.authorizationClient.authorizationForScopes([]);
      final accessToken = authorization?.accessToken;

      return await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
    } catch (e) {
      debugPrint(
          'Native Google sign-in failed ($e), falling back to browser OAuth...');
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : SupabaseConfig.authRedirect,
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
      return AuthResponse(session: _client.auth.currentSession);
    }
  }

  Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {
      // Google may not be initialized / signed in.
    }
    await _client.auth.signOut();
  }

  Future<Profile?> fetchMyProfile() async {
    final uid = currentUser?.id;
    if (uid == null) return null;
    return _profiles.getById(uid);
  }

  Future<Profile> completeOnboarding({
    required String username,
    required String bikeName,
    int? bikeYear,
    String? city,
    String? displayName,
    XFile? bikePhoto,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) {
      throw const AuthException('Not signed in');
    }

    final profile = await _profiles.update(
      uid,
      username: username.trim().toLowerCase(),
      displayName: displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : username.trim(),
      city: city?.trim(),
      onboardingCompleted: true,
    );

    final bike = await _bikes.create(
      userId: uid,
      name: bikeName.trim(),
      year: bikeYear,
      isPrimary: true,
    );
    if (bikePhoto != null) {
      try {
        await _bikes.setPhoto(bike, bikePhoto);
      } catch (e) {
        // Onboarding shouldn't fail over a photo; it can be added in Profile.
        debugPrint('Bike photo upload failed: $e');
      }
    }

    return profile;
  }
}
