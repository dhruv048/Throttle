import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data.dart';
import '../models/models.dart';
import '../repositories/bike_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/ride_repository.dart';
import '../services/ride_events.dart';
import '../theme.dart';
import '../widgets/rider_avatar.dart';
import '../widgets/ride_card.dart';
import '../widgets/route_map.dart';
import '../widgets/ui.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen(
      {super.key, required this.onStartRide, required this.onViewRoute});

  final VoidCallback onStartRide;
  final VoidCallback onViewRoute;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool joined = false;
  String _firstName = '';
  String _initials = '';
  String? _primaryBike;
  List<FeedItem>? _feed;
  String? _feedError;

  @override
  void initState() {
    super.initState();
    RideEvents.changed.addListener(_loadFeed);
    _loadUser();
    _loadFeed();
  }

  @override
  void dispose() {
    RideEvents.changed.removeListener(_loadFeed);
    super.dispose();
  }

  static String _partOfDay(DateTime now) {
    if (now.hour < 12) return 'Morning';
    if (now.hour < 17) return 'Afternoon';
    return 'Evening';
  }

  Future<void> _loadFeed() async {
    try {
      final feed = await RideRepository().feed();
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _feedError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _feedError = 'Couldn\'t load rides. Pull to retry.');
    }
  }

  Future<void> _loadUser() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final profile = await ProfileRepository().getById(uid);
      final bikes = await BikeRepository().listForUser(uid);
      if (mounted) {
        setState(() {
          if (profile != null) {
            final name = profile.displayName ?? profile.username ?? '';
            _firstName = name.split(' ').first;
            _initials = profile.initials;
          }
          if (bikes.isNotEmpty) {
            final primary =
                bikes.firstWhere((b) => b.isPrimary, orElse: () => bikes.first);
            _primaryBike = primary.name;
          }
        });
      }
    } catch (_) {
      // Offline fallback
    }
  }

  @override
  Widget build(BuildContext context) {
    final nearby = routes.first;
    final firstName = _firstName;
    final partOfDay = _partOfDay(DateTime.now());
    return RefreshIndicator(
      onRefresh: () => Future.wait([_loadFeed(), _loadUser()]),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          PageHeader(
            eyebrow: 'Good ${partOfDay.toLowerCase()}',
            title: '',
            titleSpan: TextSpan(
              children: [
                TextSpan(
                    text: firstName.isEmpty ? partOfDay : '$partOfDay, ',
                    style: displayStyle(size: 34)),
                TextSpan(
                    text: firstName,
                    style: displayStyle(size: 34, color: AppColors.primary)),
              ],
            ),
            right: Row(
              children: [
                Material(
                  color: AppColors.card,
                  shape: const CircleBorder(
                      side: BorderSide(color: AppColors.border)),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {},
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(Icons.notifications_outlined,
                          size: 16, color: AppColors.foreground),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                RiderAvatar(initials: _initials),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: RiseIn(
              delay: const Duration(milliseconds: 80),
              child: SheenButton(
                onTap: widget.onStartRide,
                child: AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const LabelMono('Ready to roll'),
                            const SizedBox(height: 4),
                            Text('Start Ride', style: displayStyle(size: 24)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const BlinkDot(),
                                const SizedBox(width: 8),
                                Text(
                                  _primaryBike ?? 'Add a bike in Profile',
                                  style: monoStyle(size: 11, tracking: 0),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 28),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: RiseIn(
              delay: const Duration(milliseconds: 160),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const LabelMono('Nearby'),
                      Text('8 km away',
                          style: monoStyle(size: 11, tracking: 0)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RouteMap(seed: nearby.seed, label: nearby.difficulty),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(nearby.name, style: displayStyle(size: 20)),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                      child: StatBlock(
                                          value: '${nearby.km}', label: 'km')),
                                  Expanded(
                                      child: StatBlock(
                                          value: nearby.time, label: 'est.')),
                                  Expanded(
                                      child: StatBlock(
                                          value: '${nearby.riders}',
                                          label: 'riders')),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: widget.onViewRoute,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.secondary,
                                    foregroundColor: AppColors.foreground,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  child: const Text('View route',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LabelMono('From your riders'),
                const SizedBox(height: 8),
                ..._buildFeed(),
                AppCard(
                  highlight: true,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          LabelMono('Group ride', color: AppColors.primary),
                          Text(groupRide.when,
                              style: monoStyle(size: 11, tracking: 0)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${groupRide.title} — ${groupRide.km} km',
                        style: displayStyle(size: 20),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${groupRide.riders + (joined ? 1 : 0)} riders · ${groupRide.spots - (joined ? 1 : 0)} spots left · meets at ${groupRide.meet}',
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.mutedForeground),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => setState(() => joined = !joined),
                          style: FilledButton.styleFrom(
                            backgroundColor: joined
                                ? AppColors.secondary
                                : AppColors.primary,
                            foregroundColor: joined
                                ? AppColors.foreground
                                : AppColors.primaryForeground,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            joined ? 'Joined ✓' : 'Join ride',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFeed() {
    final feed = _feed;
    if (feed == null && _feedError == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (feed == null || feed.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            padding: const EdgeInsets.all(16),
            child: Text(
              _feedError ?? 'No rides yet. Record one and share it!',
              style: const TextStyle(
                  fontSize: 14, color: AppColors.mutedForeground),
            ),
          ),
        ),
      ];
    }
    return [
      for (final item in feed)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: RideCard(key: ValueKey(item.ride.id), item: item),
        ),
    ];
  }
}
