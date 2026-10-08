import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/ride_sync_service.dart';
import '../theme.dart';
import 'auth/login_screen.dart';
import 'auth/onboarding_screen.dart';

/// Routes unauthenticated / incomplete profiles before the main shell.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.auth,
    required this.sync,
    required this.child,
  });

  final AuthService auth;
  final RideSyncService sync;
  final Widget child;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _authSub;
  Session? _session;
  Profile? _profile;
  bool _booting = true;
  bool _loadingProfile = false;
  String? _profileError;

  @override
  void initState() {
    super.initState();
    _session = widget.auth.session;
    _authSub = widget.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      setState(() => _session = state.session);
      if (state.session != null) {
        widget.sync.start();
        unawaited(_loadProfile());
      } else {
        setState(() {
          _profile = null;
          _profileError = null;
          _booting = false;
        });
      }
    });
    if (_session != null) {
      widget.sync.start();
      unawaited(_loadProfile());
    } else {
      _booting = false;
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loadingProfile = true;
      _profileError = null;
    });
    try {
      Profile? profile;
      for (var i = 0; i < 8; i++) {
        profile = await widget.auth.fetchMyProfile();
        if (profile != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loadingProfile = false;
        _booting = false;
        if (profile == null) {
          _profileError = 'Could not load profile yet. Try again.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
        _booting = false;
        _profileError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_session == null) {
      return LoginScreen(auth: widget.auth);
    }

    if (_loadingProfile && _profile == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_profileError != null && _profile == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_profileError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: _loadProfile, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    if (_profile == null || !_profile!.onboardingCompleted) {
      return OnboardingScreen(
        auth: widget.auth,
        initialUsername: _profile?.username,
        initialDisplayName: _profile?.displayName,
        onCompleted: (profile) {
          setState(() => _profile = profile);
          widget.sync.start();
        },
      );
    }

    return widget.child;
  }
}
