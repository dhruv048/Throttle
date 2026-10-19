import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/live.dart';
import '../providers/navigation.dart';
import '../providers/rider.dart';
import '../providers/rides.dart';
import '../format.dart';
import '../services/achievements.dart';
import '../widgets/badges.dart';
import '../providers/core.dart';
import '../theme.dart';
import '../units.dart';
import 'rider_profile_screen.dart';
import '../widgets/follow_button.dart';
import '../widgets/ride_card.dart';
import '../widgets/rider_avatar.dart';
import '../widgets/skeleton.dart';
import '../widgets/ui.dart';

enum _Tab { latest, popular, riders, achievements }

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  /// Reloads what Discover shows; each list keeps its current (real) data
  /// until the new data arrives.
  static Future<void> refresh(WidgetRef ref) {
    ref.invalidate(riderSearchProvider);
    return refreshAll(ref, [
      homeFeedProvider.future,
      popularRidesProvider.future,
      followingProvider.future,
      leaderboardProvider.future,
    ]);
  }

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  _Tab _tab = _Tab.latest;

  /// What's typed in the search box, and what riders were searched for: the
  /// same once typing pauses.
  String _query = '';
  String _searched = '';
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _refresh() => refreshAll(ref, [
        leaderboardProvider.future,
        homeFeedProvider.future,
        popularRidesProvider.future,
        followingProvider.future,
        riderSearchProvider(_searched).future,
      ]);

  void _onSearch(String value) {
    setState(() => _query = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300),
        () => setState(() => _searched = value));
  }

  @override
  Widget build(BuildContext context) {
    // Every tab loads up front, so switching between them is instant.
    final latest = ref.watch(homeFeedProvider);
    final leaders = ref.watch(leaderboardProvider);
    final rides = ref.watch(popularRidesProvider);
    final riders = ref.watch(riderSearchProvider(_searched));
    // Who the rider follows, for the Follow buttons, before they're shown.
    ref.watch(followingProvider);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          const PageHeader(eyebrow: 'Riders & rides', title: 'Discover'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search,
                          size: 16, color: AppColors.mutedForeground),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          onChanged: _onSearch,
                          decoration: const InputDecoration(
                            hintText: 'Search riders and rides',
                            hintStyle: TextStyle(
                                fontSize: 14, color: AppColors.mutedForeground),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.start,
                    runSpacing: 8,
                    children: [
                      _tabChip('Latest', _Tab.latest),
                      _tabChip('Popular', _Tab.popular),
                      _tabChip('Riders', _Tab.riders),
                      _tabChip('Achievements', _Tab.achievements),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: switch (_tab) {
                _Tab.latest => _ridesTab(latest,
                    label: 'Latest rides',
                    empty: 'No rides yet. Follow riders to see theirs here.'),
                _Tab.popular => _ridesTab(rides,
                    label: 'Popular this month',
                    empty: 'No public rides in the last 30 days yet.'),
                _Tab.riders => _ridersTab(riders),
                _Tab.achievements => _achievementsTab(leaders),
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _ridesTab(AsyncValue<List<FeedItem>> rides,
      {required String label, required String empty}) {
    final deleted = ref.watch(deletedRidesProvider);
    final q = _query.trim().toLowerCase();
    final shown = rides.value
        ?.where((f) =>
            !deleted.contains(f.ride.id) &&
            (q.isEmpty ||
                f.ride.title.toLowerCase().contains(q) ||
                (f.ride.endPlace ?? '').toLowerCase().contains(q) ||
                (f.rider.displayName ?? '').toLowerCase().contains(q) ||
                (f.rider.username ?? '').toLowerCase().contains(q)))
        .toList();
    return [
      LabelMono(label),
      const SizedBox(height: 8),
      if (shown == null && rides.isLoading)
        const RideListSkeleton()
      else if (shown == null)
        _message('Couldn\'t load rides. Pull down to retry.')
      else if (shown.isEmpty)
        _message(q.isEmpty ? empty : 'No rides match "$_query".')
      else
        for (final item in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RideCard(key: ValueKey(item.ride.id), item: item),
          ),
    ];
  }

  List<Widget> _ridersTab(AsyncValue<List<Profile>> search) {
    // Old results don't match a new search: placeholders until it's done.
    final riders = _query == _searched ? search.value : null;
    return [
      LabelMono(_query.trim().isEmpty ? 'Riders' : 'Results'),
      const SizedBox(height: 8),
      if (riders == null && (search.isLoading || _query != _searched))
        for (var i = 0; i < 4; i++) const PersonRowSkeleton()
      else if (riders == null)
        _message('Couldn\'t load riders. Pull down to retry.')
      else if (riders.isEmpty)
        _message(_query.trim().isEmpty
            ? 'No other riders yet.'
            : 'No riders match "$_query".')
      else
        for (final rider in riders)
          _RiderRow(key: ValueKey(rider.id), rider: rider),
    ];
  }

  /// Riders by badges earned, then who holds each record.
  List<Widget> _achievementsTab(AsyncValue<List<RiderStanding>> state) {
    final q = _query.trim().toLowerCase();
    final all = state.value;
    if (all == null) {
      return [
        const LabelMono('Most achievements'),
        const SizedBox(height: 8),
        if (state.isLoading)
          for (var i = 0; i < 4; i++) const PersonRowSkeleton()
        else
          _message('Couldn\'t load achievements. Pull down to retry.'),
      ];
    }
    final uid = ref.watch(currentUserIdProvider);
    final ranked = [...all]..sort((a, b) {
        final byBadges = b.badges.length.compareTo(a.badges.length);
        return byBadges != 0 ? byBadges : b.totals.km.compareTo(a.totals.km);
      });
    final shown = [
      for (var i = 0; i < ranked.length; i++)
        if (q.isEmpty ||
            (ranked[i].rider.displayName ?? '').toLowerCase().contains(q) ||
            (ranked[i].rider.username ?? '').toLowerCase().contains(q))
          (rank: i + 1, standing: ranked[i]),
    ].take(10).toList();
    return [
      const LabelMono('Most achievements'),
      const SizedBox(height: 8),
      if (shown.isEmpty)
        _message(q.isEmpty
            ? 'No rides yet. Badges show up here as riders earn them.'
            : 'No riders match "$_query".')
      else
        for (final s in shown)
          _StandingRow(
            key: ValueKey(s.standing.rider.id),
            rank: s.rank,
            standing: s.standing,
            me: s.standing.rider.id == uid,
          ),
      if (all.isNotEmpty) ...[
        const SizedBox(height: 16),
        const LabelMono('Record holders'),
        const SizedBox(height: 8),
        _RecordHolders(standings: all, me: uid),
      ],
    ];
  }

  Widget _message(String text) => AppCard(
        padding: const EdgeInsets.all(16),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14, color: AppColors.mutedForeground)),
      );

  Widget _tabChip(String label, _Tab value) {
    final on = _tab == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _tab = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: on ? AppColors.foreground : AppColors.card,
            borderRadius: BorderRadius.circular(999),
            border:
                Border.all(color: on ? AppColors.foreground : AppColors.border),
          ),
          child: Text(
            label.toUpperCase(),
            style: monoStyle(
              size: 11,
              tracking: 1.32,
              color: on ? AppColors.background : AppColors.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}

class _RiderRow extends StatelessWidget {
  const _RiderRow({super.key, required this.rider});

  final Profile rider;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => openRiderProfile(context, rider),
        behavior: HitTestBehavior.opaque,
        child: AppCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              RiderAvatar(initials: rider.initials, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rider.displayName ?? rider.username ?? 'Rider',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(
                      [
                        if (rider.username != null) '@${rider.username}',
                        if (rider.city?.isNotEmpty == true) rider.city!,
                      ].join(' · '),
                      style: monoStyle(size: 11, tracking: 0),
                    ),
                  ],
                ),
              ),
              FollowButton(riderId: rider.id),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rider's place on the leaderboard, and their best badges.
class _StandingRow extends StatelessWidget {
  const _StandingRow({
    super.key,
    required this.rank,
    required this.standing,
    required this.me,
  });

  final int rank;
  final RiderStanding standing;
  final bool me;

  /// Their three most advanced badges: the hardest of each kind they've
  /// earned, furthest up its kind's tiers first.
  List<RideBadge> get _best {
    final byKind = <BadgeKind, (RideBadge, int)>{};
    for (final b in standing.badges) {
      final tier = (byKind[b.kind]?.$2 ?? -1) + 1;
      byKind[b.kind] = (b, tier); // later ones are harder
    }
    final best = byKind.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final (badge, _) in best.take(3)) badge];
  }

  @override
  Widget build(BuildContext context) {
    final rider = standing.rider;
    final badges = standing.badges.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => openRiderProfile(context, rider),
        behavior: HitTestBehavior.opaque,
        child: AppCard(
          highlight: me,
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text('$rank',
                    style: displayStyle(
                        size: 22,
                        color: rank <= 3
                            ? AppColors.primary
                            : AppColors.mutedForeground)),
              ),
              RiderAvatar(initials: rider.initials, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${rider.displayName ?? rider.username ?? 'Rider'}'
                        '${me ? ' (you)' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                        '$badges ${badges == 1 ? 'badge' : 'badges'} · '
                        '${context.units.totalText(standing.totals.km)}',
                        style: monoStyle(size: 11, tracking: 0)),
                  ],
                ),
              ),
              for (final b in _best)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: BadgeMedal(b, size: 28),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who holds each record: most km, flags, the longest ride, most climbed,
/// most places reached.
class _RecordHolders extends StatelessWidget {
  const _RecordHolders({required this.standings, required this.me});

  final List<RiderStanding> standings;
  final String? me;

  static final _records = <(
    String,
    IconData,
    double Function(RiderTotals),
    String Function(double, Units)
  )>[
    (
      'Most distance ridden',
      Icons.emoji_events_rounded,
      (t) => t.km,
      (v, u) => u.totalText(v)
    ),
    (
      'Most flags planted',
      Icons.flag_rounded,
      (t) => t.rides.toDouble(),
      (v, _) => '${v.round()}'
    ),
    (
      'Longest ride',
      Icons.route_rounded,
      (t) => t.longestKm,
      (v, u) => u.totalText(v)
    ),
    (
      'Most climbed',
      Icons.terrain_rounded,
      (t) => t.climbM,
      (v, _) => '${formatNumber(v.round())} m'
    ),
    (
      'Most places reached',
      Icons.explore_rounded,
      (t) => t.places.toDouble(),
      (v, _) => '${v.round()}'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final (label, icon, measure, show) in _records) {
      RiderStanding? leader;
      for (final s in standings) {
        if (measure(s.totals) > 0 &&
            (leader == null || measure(s.totals) > measure(leader.totals))) {
          leader = s;
        }
      }
      if (leader == null) continue;
      final rider = leader.rider;
      if (rows.isNotEmpty) {
        rows.add(const Divider(height: 1, indent: 64, color: AppColors.border));
      }
      rows.add(InkWell(
        onTap: () => openRiderProfile(context, rider),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                    color: AppColors.accent, shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LabelMono(label),
                    const SizedBox(height: 2),
                    Text(
                        '${rider.displayName ?? rider.username ?? 'Rider'}'
                        '${rider.id == me ? ' (you)' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: displayStyle(size: 16)),
                  ],
                ),
              ),
              Text(show(measure(leader.totals), context.units),
                  style: displayStyle(size: 18, color: AppColors.primary)),
            ],
          ),
        ),
      ));
    }
    return AppCard(child: Column(children: rows));
  }
}
