import 'package:flutter/material.dart';
import '../data.dart';
import '../theme.dart';
import '../widgets/rider_avatar.dart';
import '../widgets/route_map.dart';
import '../widgets/ui.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onStartRide, required this.onViewRoute});

  final VoidCallback onStartRide;
  final VoidCallback onViewRoute;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool joined = false;

  @override
  Widget build(BuildContext context) {
    final nearby = routes.first;
    final firstName = me.name.split(' ').first;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        PageHeader(
          eyebrow: 'Good morning',
          title: '',
          titleSpan: TextSpan(
            children: [
              TextSpan(text: 'Morning, ', style: displayStyle(size: 34)),
              TextSpan(text: firstName, style: displayStyle(size: 34, color: AppColors.primary)),
            ],
          ),
          right: Row(
            children: [
              Material(
                color: AppColors.card,
                shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {},
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(Icons.notifications_outlined, size: 16, color: AppColors.foreground),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              RiderAvatar(initials: me.initials),
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
                                'Yamaha MT-15 · Followers',
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
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
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
                    Text('8 km away', style: monoStyle(size: 11, tracking: 0)),
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
                                Expanded(child: StatBlock(value: '${nearby.km}', label: 'km')),
                                Expanded(child: StatBlock(value: nearby.time, label: 'est.')),
                                Expanded(child: StatBlock(value: '${nearby.riders}', label: 'riders')),
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
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('View route', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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
              ...rides.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: RideCard(ride: r),
                  )),
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
                        Text(groupRide.when, style: monoStyle(size: 11, tracking: 0)),
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
                      style: const TextStyle(fontSize: 14, color: AppColors.mutedForeground),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => setState(() => joined = !joined),
                        style: FilledButton.styleFrom(
                          backgroundColor: joined ? AppColors.secondary : AppColors.primary,
                          foregroundColor: joined ? AppColors.foreground : AppColors.primaryForeground,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          joined ? 'Joined ✓' : 'Join ride',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
    );
  }
}

class RideCard extends StatefulWidget {
  const RideCard({super.key, required this.ride});

  final Ride ride;

  @override
  State<RideCard> createState() => _RideCardState();
}

class _RideCardState extends State<RideCard> {
  bool liked = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.ride;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                RiderAvatar(initials: r.initials),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.rider, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      Text('${r.ago} · ${r.bike}', style: monoStyle(size: 11, tracking: 0)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title, style: displayStyle(size: 18)),
                Text('${r.from} → ${r.to}', style: const TextStyle(fontSize: 14, color: AppColors.mutedForeground)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(child: StatBlock(value: '${r.km}', label: 'km')),
                Expanded(child: StatBlock(value: r.duration, label: 'time')),
                Expanded(child: StatBlock(value: formatNumber(r.elev), label: 'm elev')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          RouteMap(seed: r.seed, height: 112),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => liked = !liked),
                  child: Row(
                    children: [
                      Icon(
                        liked ? Icons.favorite : Icons.favorite_border,
                        size: 16,
                        color: liked ? AppColors.primary : AppColors.mutedForeground,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${r.kudos + (liked ? 1 : 0)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: liked ? AppColors.primary : AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                const Icon(Icons.chat_bubble_outline, size: 16, color: AppColors.mutedForeground),
                const SizedBox(width: 6),
                Text('${r.comments}', style: const TextStyle(fontSize: 14, color: AppColors.mutedForeground)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
