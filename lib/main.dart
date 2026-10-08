import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/activity_screen.dart';
import 'screens/auth_gate.dart';
import 'screens/discover_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/record_screen.dart';
import 'services/auth_service.dart';
import 'services/ride_sync_service.dart';
import 'theme.dart';
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
      anonKey: SupabaseConfig.anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  runApp(const ThrottleApp());
}

class ThrottleApp extends StatefulWidget {
  const ThrottleApp({
    super.key,
    this.auth,
    this.sync,
    this.home,
  });

  final AuthService? auth;
  final RideSyncService? sync;
  final Widget? home;

  @override
  State<ThrottleApp> createState() => _ThrottleAppState();
}

class _ThrottleAppState extends State<ThrottleApp> {
  AuthService? _auth;
  RideSyncService? _sync;

  @override
  void initState() {
    super.initState();
    if (widget.home != null) return;
    if (widget.auth != null && widget.sync != null) {
      _auth = widget.auth;
      _sync = widget.sync;
    } else if (SupabaseConfig.isConfigured) {
      try {
        _auth = AuthService();
        _sync = RideSyncService();
      } catch (e) {
        debugPrint('Supabase not yet initialized: $e');
      }
    }
  }

  @override
  void dispose() {
    if (widget.sync == null) {
      _sync?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget homeWidget;
    if (widget.home != null) {
      homeWidget = widget.home!;
    } else if (_auth != null && _sync != null) {
      homeWidget = AuthGate(
        auth: _auth!,
        sync: _sync!,
        child: const Shell(),
      );
    } else {
      homeWidget = const _MissingConfigScreen();
    }

    return MaterialApp(
      title: 'Throttle — Ride, record, share',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: homeWidget,
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

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
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
                    index: index,
                    children: [
                      HomeScreen(
                        onStartRide: () => setState(() => index = 2),
                        onViewRoute: () => setState(() => index = 1),
                      ),
                      const DiscoverScreen(),
                      const RecordScreen(),
                      const ActivityScreen(),
                      const ProfileScreen(),
                    ],
                  ),
                ),
              ),
              ThrottleBottomNav(
                index: index,
                onChanged: (i) => setState(() => index = i),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
