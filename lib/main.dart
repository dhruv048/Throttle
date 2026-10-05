import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/activity_screen.dart';
import 'screens/discover_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/record_screen.dart';
import 'theme.dart';
import 'widgets/bottom_nav.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const ThrottleApp());
}
//27.710217,
//27.705580, 85.322993
//27.721001, 85.335114
class ThrottleApp extends StatelessWidget {
  const ThrottleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Throttle — Ride, record, share',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const Shell(),
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
