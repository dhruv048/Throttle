import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'providers/core.dart';
import 'providers/navigation.dart';
import 'screens/activity_screen.dart';
import 'screens/auth_gate.dart';
import 'screens/discover_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/record_screen.dart';
import 'providers/settings.dart';
import 'theme.dart';
import 'units.dart';
import 'widgets/bottom_nav.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  if (!SupabaseConfig.isConfigured) {
    debugPrint(
      'Supabase is not configured. Set SUPABASE_URL / SUPABASE_ANON_KEY '
      '(see supabase/README.md).',
    );
  } else {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  runApp(const ProviderScope(retry: noRetry, child: ThrottleApp()));
}

class ThrottleApp extends ConsumerWidget {
  const ThrottleApp({super.key, this.home});

  /// Shown instead of the signed-in app (tests).
  final Widget? home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitsProvider);
    return MaterialApp(
      title: 'Throttle — Ride, record, share',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // Km or miles, on every page.
      builder: (context, child) =>
          UnitsScope(units: units, child: child ?? const SizedBox.shrink()),
      home: home ??
          (SupabaseConfig.isConfigured
              ? const AuthGate(child: Shell())
              : const _MissingConfigScreen()),
    );
  }
}

class _MissingConfigScreen extends StatelessWidget {
  const _MissingConfigScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Throttle', style: displayStyle(size: 34)),
              const SizedBox(height: 12),
              const Text(
                'Add your Supabase URL and anon key, then restart the app.\n\n'
                'See supabase/README.md for setup steps.',
                style: TextStyle(height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the background: the visible tab refreshes.
    if (state == AppLifecycleState.resumed) {
      _refresh(ref.read(currentTabProvider));
    }
  }

  Future<void> _refresh(AppTab tab) => switch (tab) {
        AppTab.home => HomeScreen.refresh(ref),
        AppTab.discover => DiscoverScreen.refresh(ref),
        // Nothing to reload; GPS follows the tab by itself.
        AppTab.record => Future.value(),
        AppTab.activity => ActivityScreen.refresh(ref),
        AppTab.profile => ProfileScreen.refresh(ref),
      };

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(currentTabProvider);
    // Every tab stays alive in the IndexedStack, and refreshes when it comes
    // on screen.
    ref.listen(currentTabProvider, (previous, next) {
      if (next != previous) _refresh(next);
    });
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            children: [
              Expanded(
                child: SafeArea(
                  bottom: false,
                  child: IndexedStack(
                    index: tab.index,
                    children: const [
                      HomeScreen(),
                      DiscoverScreen(),
                      RecordScreen(),
                      ActivityScreen(),
                      ProfileScreen(),
                    ],
                  ),
                ),
              ),
              ThrottleBottomNav(
                index: tab.index,
                onChanged: (i) => ref
                    .read(currentTabProvider.notifier)
                    .show(AppTab.values[i]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
