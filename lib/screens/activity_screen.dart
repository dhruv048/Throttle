import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data.dart';
import '../models/models.dart';
import '../repositories/profile_repository.dart';
import '../repositories/ride_repository.dart';
import '../services/ride_events.dart';
import '../theme.dart';
import '../widgets/ride_card.dart';
import '../widgets/ui.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  static const _pageSize = 20;
  static const _monthlyGoalKm = 500.0;
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  late final _repo = RideRepository();
  RideStats _stats = RideStats.empty;
  List<FeedItem> _pending = [];
  List<FeedItem> _rides = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    RideEvents.changed.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    RideEvents.changed.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final gen = ++_generation;
    String? uid;
    try {
      uid = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      // Supabase not initialised (e.g. widget tests).
    }
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // Local rides first: they're available offline.
    final pending = await _repo.myPendingRides();
    Profile me = Profile(id: uid);
    List<RideRecord> history = [];
    List<FeedItem> firstPage = [];
    String? error;
    try {
      final results = await Future.wait([
        ProfileRepository().getById(uid),
        _repo.myRideHistory(),
        _repo.myRides(limit: _pageSize),
      ]);
      me = results[0] as Profile? ?? me;
      history = results[1] as List<RideRecord>;
      firstPage = results[2] as List<FeedItem>;
    } catch (_) {
      error = 'Offline — showing rides saved on this device.';
    }
    if (!mounted || gen != _generation) return;

    // A ride can be uploaded a moment before the local queue marks it synced.
    final uploaded = history.map((r) => r.localId).whereType<String>().toSet();
    final unsynced =
        pending.where((p) => !uploaded.contains(p.localId)).toList();

    setState(() {
      _stats = RideStats.compute(
        [...history, ...unsynced.map((p) => p.toRecord())],
        now: DateTime.now(),
      );
      _pending = [
        for (final p in unsynced)
          FeedItem(
            ride: p.toRecord(),
            rider: me,
            bikeName: p.bikeName,
            points: p.points,
            pending: true,
          ),
      ];
      if (error == null) {
        _rides = firstPage;
        _hasMore = firstPage.length == _pageSize;
      }
      _error = error;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final gen = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.myRides(offset: _rides.length, limit: _pageSize);
      if (!mounted || gen != _generation) return;
      setState(() {
        _rides = [..._rides, ...page];
        _hasMore = page.length == _pageSize;
      });
    } catch (_) {
      // Keep what we have; the button stays for a retry.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekly = _stats.weeklyKm;
    final maxWeek = weekly.fold<double>(0, (a, b) => a > b ? a : b);
    final goalProgress = (_stats.monthKm / _monthlyGoalKm).clamp(0.0, 1.0);
    final allRides = [..._pending, ..._rides];

    return RefreshIndicator(
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600) _loadMore();
          return false;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            PageHeader(eyebrow: 'This year · ${now.year}', title: 'Activity'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.55,
                children: [
                  _stat(formatDistance(_stats.km), 'km ridden'),
                  _stat('${_stats.rides}', 'rides'),
                  _stat(formatNumber(_stats.elevationM.round()), 'm climbed'),
                  _stat((_stats.movingSecs / 3600).toStringAsFixed(1), 'hours'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const LabelMono('Weekly km'),
                        Text('This week ${formatDistance(weekly.last)} km',
                            style: monoStyle(
                                size: 11,
                                tracking: 0,
                                color: AppColors.primary)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 128,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < weekly.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: Tooltip(
                                message: '${formatDistance(weekly[i])} km',
                                child: Container(
                                  // Keep a sliver visible for empty weeks.
                                  height: maxWeek > 0
                                      ? 4 + (weekly[i] / maxWeek) * 124
                                      : 4,
                                  decoration: BoxDecoration(
                                    color: i == weekly.length - 1
                                        ? AppColors.primary
                                        : AppColors.secondary,
                                    borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(6)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('8 weeks ago',
                            style: monoStyle(size: 10, tracking: 0)),
                        Text('This week',
                            style: monoStyle(size: 10, tracking: 0)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LabelMono('Challenge'),
                    const SizedBox(height: 4),
                    Text(
                        '${_months[now.month - 1]} ${_monthlyGoalKm.round()} km',
                        style: displayStyle(size: 20)),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: goalProgress,
                        minHeight: 8,
                        backgroundColor: AppColors.secondary,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${formatDistance(_stats.monthKm)} / ${_monthlyGoalKm.round()} km',
                      style: monoStyle(size: 11, tracking: 0),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LabelMono('Your rides'),
                  const SizedBox(height: 8),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.mutedForeground)),
                    ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (allRides.isEmpty)
                    const AppCard(
                      padding: EdgeInsets.all(16),
                      child: Text('No rides yet. Hit Record and go ride!',
                          style: TextStyle(
                              fontSize: 14, color: AppColors.mutedForeground)),
                    )
                  else ...[
                    for (final item in allRides)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child:
                            RideCard(key: ValueKey(item.ride.id), item: item),
                      ),
                    if (_hasMore)
                      Center(
                        child: _loadingMore
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(),
                              )
                            : TextButton(
                                onPressed: _loadMore,
                                child: const Text('Load more')),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String v, String l) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(v, style: displayStyle(size: 30)),
          ),
          const SizedBox(height: 8),
          LabelMono(l),
        ],
      ),
    );
  }
}
