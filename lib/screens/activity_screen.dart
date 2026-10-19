import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models/models.dart';
import '../providers/core.dart';
import '../providers/navigation.dart';
import '../providers/rider.dart';
import '../providers/rides.dart';
import '../services/achievements.dart';
import '../theme.dart';
import '../units.dart';
import '../widgets/badges.dart';
import '../widgets/ride_card.dart';
import '../widgets/skeleton.dart';
import '../widgets/ui.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

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

  /// Reloads what Activity shows; it keeps showing the current (real) data
  /// until the new data arrives.
  static Future<void> refresh(WidgetRef ref) => refreshAll(ref, [
        myPendingRidesProvider.future,
        myRideHistoryProvider.future,
        myRidesProvider.future,
        myProfileProvider.future,
      ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final pendingState = ref.watch(myPendingRidesProvider);
    final historyState = ref.watch(myRideHistoryProvider);
    final pagesState = ref.watch(myRidesProvider);
    final history = historyState.value;

    // A ride can be uploaded a moment before the local queue marks it synced.
    final uploaded = (history ?? const <RideRecord>[])
        .map((r) => r.localId)
        .whereType<String>()
        .toSet();
    final unsynced = (pendingState.value ?? const <PendingRide>[])
        .where((p) => !uploaded.contains(p.localId))
        .toList();

    // Never shown from partial data: totals wait for the full history.
    final stats = history != null && pendingState.hasValue
        ? RideStats.compute(
            [...history, ...unsynced.map((p) => p.toRecord())],
            now: now,
          )
        : null;
    final String? error;
    if (!historyState.hasError && !pagesState.hasError) {
      error = null;
    } else if (stats == null) {
      error = 'Couldn\'t load your activity. Pull down to retry.';
    } else {
      error = 'Couldn\'t refresh — showing what loaded earlier.';
    }

    return RefreshIndicator(
      onRefresh: () => refresh(ref),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600) {
            ref.read(myRidesProvider.notifier).loadMore();
          }
          return false;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            PageHeader(eyebrow: 'This year · ${now.year}', title: 'Activity'),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(error,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.mutedForeground)),
              ),
            if (stats != null)
              ..._statsSection(stats, now, context.units)
            else if (historyState.isLoading || pendingState.isLoading)
              ..._statsSkeleton(now, context.units),
            if (stats != null)
              _achievements(RiderTotals.of(
                  [...history!, ...unsynced.map((p) => p.toRecord())])),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LabelMono('Your rides'),
                  const SizedBox(height: 8),
                  ..._ridesSection(ref, unsynced, pagesState),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Every badge: earned, or how close.
  Widget _achievements(RiderTotals totals) {
    final earned = RideBadge.earned(totals).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: LabelMono('Achievements')),
              Text('$earned of ${RideBadge.all.length}',
                  style: monoStyle(
                      size: 11, tracking: 0, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 18),
            child: BadgeGrid(totals: totals),
          ),
        ],
      ),
    );
  }

  List<Widget> _statsSection(RideStats stats, DateTime now, Units units) {
    final weekly = stats.weeklyKm;
    final maxWeek = weekly.fold<double>(0, (a, b) => a > b ? a : b);
    final goalProgress = (stats.monthKm / _monthlyGoalKm).clamp(0.0, 1.0);
    return [
      _grid([
        _stat(units.total(stats.km), '${units.distanceUnit} ridden'),
        _stat('${stats.rides}', 'rides'),
        _stat(formatNumber(stats.elevationM.round()), 'm climbed'),
        _stat((stats.movingSecs / 3600).toStringAsFixed(1), 'hours'),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  LabelMono('Weekly ${units.distanceUnit}'),
                  Text('This week ${units.totalText(weekly.last)}',
                      style: monoStyle(
                          size: 11, tracking: 0, color: AppColors.primary)),
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
                          message: units.totalText(weekly[i]),
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
              _chartAxis(),
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
                  '${_months[now.month - 1]} '
                  '${units.distance(_monthlyGoalKm).round()} ${units.distanceUnit}',
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
                '${units.total(stats.monthKm)} / '
                '${units.distance(_monthlyGoalKm).round()} ${units.distanceUnit}',
                style: monoStyle(size: 11, tracking: 0),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  /// Same layout as [_statsSection], with placeholders where numbers go.
  List<Widget> _statsSkeleton(DateTime now, Units units) {
    Widget tile(String label) => AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Shimmer(child: SkeletonBox(width: 76, height: 30)),
              const SizedBox(height: 8),
              LabelMono(label),
            ],
          ),
        );
    return [
      _grid([
        tile('${units.distanceUnit} ridden'),
        tile('rides'),
        tile('m climbed'),
        tile('hours'),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  LabelMono('Weekly ${units.distanceUnit}'),
                  const Shimmer(child: SkeletonBox(width: 90, height: 11)),
                ],
              ),
              const SizedBox(height: 16),
              const Shimmer(child: SkeletonBox(height: 128)),
              const SizedBox(height: 6),
              _chartAxis(),
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
                  '${_months[now.month - 1]} '
                  '${units.distance(_monthlyGoalKm).round()} ${units.distanceUnit}',
                  style: displayStyle(size: 20)),
              const SizedBox(height: 12),
              const Shimmer(child: SkeletonBox(height: 8, radius: 999)),
              const SizedBox(height: 8),
              const Shimmer(child: SkeletonBox(width: 90, height: 11)),
            ],
          ),
        ),
      ),
    ];
  }

  /// Rides still on this phone first (they're the newest), then the
  /// uploaded ones, a page at a time.
  List<Widget> _ridesSection(WidgetRef ref, List<PendingRide> unsynced,
      AsyncValue<RidePages> pagesState) {
    // Saved on this phone, so shown even offline.
    final me = ref.watch(myProfileProvider).value ??
        Profile(id: ref.watch(currentUserIdProvider) ?? '');
    final pages = pagesState.value;
    final all = [
      for (final p in unsynced)
        FeedItem(
          ride: p.toRecord(),
          rider: me,
          bikeName: p.bikeName,
          points: p.points,
          pending: true,
        ),
      ...?pages?.items,
    ];
    return [
      for (final item in all)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: RideCard(key: ValueKey(item.ride.id), item: item),
        ),
      if (pages == null && pagesState.isLoading)
        const RideListSkeleton()
      else if (pages != null && all.isEmpty)
        const AppCard(
          padding: EdgeInsets.all(16),
          child: Text('No rides yet. Hit Record and go ride!',
              style: TextStyle(fontSize: 14, color: AppColors.mutedForeground)),
        )
      else if (pages?.hasMore ?? false)
        Center(
          child: pages!.loadingMore
              ? const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: RideCardSkeleton(),
                )
              : TextButton(
                  onPressed: () =>
                      ref.read(myRidesProvider.notifier).loadMore(),
                  child: const Text('Load more')),
        ),
    ];
  }

  Widget _grid(List<Widget> tiles) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.55,
        children: tiles,
      ),
    );
  }

  Widget _chartAxis() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('8 weeks ago', style: monoStyle(size: 10, tracking: 0)),
          Text('This week', style: monoStyle(size: 10, tracking: 0)),
        ],
      );

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
