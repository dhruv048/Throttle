import 'package:flutter/material.dart';

import '../services/achievements.dart';
import '../theme.dart';
import 'ui.dart';

IconData badgeIcon(RideBadge badge) => switch (badge.kind) {
      BadgeKind.flags => Icons.flag_rounded,
      BadgeKind.distance => Icons.emoji_events_rounded,
      BadgeKind.longRide => Icons.route_rounded,
      BadgeKind.climb => Icons.terrain_rounded,
      BadgeKind.explorer => Icons.explore_rounded,
      BadgeKind.saddle => Icons.timer_rounded,
    };

/// A badge as a medal: lit orange once earned; grey, with a ring showing
/// the way there, until then.
class BadgeMedal extends StatelessWidget {
  const BadgeMedal(this.badge,
      {super.key, this.earned = true, this.progress = 1, this.size = 52});

  final RideBadge badge;
  final bool earned;

  /// 0 → 1, shown while it isn't [earned].
  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Container(
              margin: EdgeInsets.all(size * 0.08),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: earned
                    ? RadialGradient(
                        center: const Alignment(-0.35, -0.45),
                        colors: [
                          Color.lerp(AppColors.primary, Colors.white, 0.35)!,
                          AppColors.primary,
                          Color.lerp(AppColors.primary, Colors.black, 0.2)!,
                        ],
                        stops: const [0, 0.55, 1],
                      )
                    : null,
                color: earned ? null : AppColors.panel,
                boxShadow: earned
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: size * 0.25,
                          offset: Offset(0, size * 0.06),
                        ),
                      ]
                    : null,
              ),
              child: Icon(badgeIcon(badge),
                  size: size * 0.42,
                  color: earned ? Colors.white : AppColors.mutedForeground),
            ),
          ),
          if (!earned)
            SizedBox.square(
              dimension: size,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: size * 0.06,
                color: AppColors.primary,
                backgroundColor: AppColors.border,
              ),
            ),
        ],
      ),
    );
  }
}

/// Every badge for [totals], earned ones first, then those nearest to
/// being earned. Tap one for what it takes.
class BadgeGrid extends StatelessWidget {
  const BadgeGrid({super.key, required this.totals});

  final RiderTotals totals;

  @override
  Widget build(BuildContext context) {
    final badges = [...RideBadge.all]..sort((a, b) {
        final ea = a.earnedBy(totals), eb = b.earnedBy(totals);
        if (ea != eb) return ea ? -1 : 1;
        return b.progress(totals).compareTo(a.progress(totals));
      });
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final width = (constraints.maxWidth - 2 * gap) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: 14,
          children: [
            for (final b in badges)
              SizedBox(
                width: width,
                child: _BadgeTile(badge: b, totals: totals),
              ),
          ],
        );
      },
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, required this.totals});

  final RideBadge badge;
  final RiderTotals totals;

  @override
  Widget build(BuildContext context) {
    final earned = badge.earnedBy(totals);
    return Semantics(
      button: true,
      label: '${badge.title}, ${earned ? 'earned' : 'not earned yet'}',
      child: GestureDetector(
        onTap: () => _explain(context, earned),
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            BadgeMedal(badge,
                earned: earned, progress: badge.progress(totals), size: 58),
            const SizedBox(height: 6),
            Text(badge.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: earned
                        ? AppColors.foreground
                        : AppColors.mutedForeground)),
            const SizedBox(height: 2),
            Text(earned ? 'Earned' : badge.progressText(totals),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(
                    size: 10,
                    tracking: 0,
                    color: earned ? AppColors.primary : null)),
          ],
        ),
      ),
    );
  }

  void _explain(BuildContext context, bool earned) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BadgeMedal(badge,
                  earned: earned, progress: badge.progress(totals), size: 88),
              const SizedBox(height: 14),
              Text(badge.title, style: displayStyle(size: 26)),
              const SizedBox(height: 6),
              Text(badge.description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, color: AppColors.mutedForeground)),
              const SizedBox(height: 14),
              earned
                  ? const LabelMono('Earned', color: AppColors.primary)
                  : Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: badge.progress(totals),
                            minHeight: 8,
                            backgroundColor: AppColors.secondary,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(badge.progressText(totals),
                            style: monoStyle(size: 12, tracking: 0)),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
