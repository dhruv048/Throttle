import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core.dart';
import '../providers/live.dart';
import '../providers/rider.dart';
import '../theme.dart';
import '../widgets/skeleton.dart';
import 'auth/login_screen.dart';
import 'auth/onboarding_screen.dart';

/// Routes unauthenticated / incomplete profiles before the main shell.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // While a rider is signed in, rides saved on this phone upload and
    // changes made elsewhere stream in.
    ref.watch(rideSyncProvider);
    ref.watch(realtimeProvider);

    if (ref.watch(sessionProvider) == null) return const LoginScreen();

    final profile = ref.watch(myProfileProvider);
    if (profile.isLoading && !profile.hasValue) return const PageSkeleton();

    final loaded = profile.value;
    if (loaded == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  profile.hasError
                      ? '${profile.error}'
                      : 'Could not load profile yet. Try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(myProfileProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!loaded.onboardingCompleted) {
      return OnboardingScreen(
        initialUsername: loaded.username,
        initialDisplayName: loaded.displayName,
        onCompleted: (profile) =>
            ref.read(myProfileProvider.notifier).set(profile),
      );
    }

    return child;
  }
}
