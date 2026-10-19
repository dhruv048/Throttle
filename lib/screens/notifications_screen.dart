import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models/models.dart';
import '../providers/core.dart';
import '../providers/navigation.dart';
import '../providers/notifications.dart';
import '../theme.dart';
import '../widgets/follow_button.dart';
import '../widgets/rider_avatar.dart';
import '../widgets/skeleton.dart';
import '../widgets/ui.dart';
import 'ride_detail_screen.dart';
import 'rider_profile_screen.dart';

/// Kudos on the rider's rides and new followers, newest first. Opening it
/// marks them all read; the ones that were new stay marked "new" while it's
/// open.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Unread when the screen opened.
  Set<String>? _new;

  @override
  void initState() {
    super.initState();
    ref.listenManual(notificationsProvider, (_, next) {
      final list = next.value;
      if (list == null || _new != null) return;
      setState(() => _new = {
            for (final n in list)
              if (n.unread) n.id
          });
      if (_new!.isNotEmpty) _markRead();
    }, fireImmediately: true);
  }

  Future<void> _markRead() async {
    try {
      await ref.read(notificationRepositoryProvider).markAllRead();
    } catch (_) {
      // They stay unread, and are marked next time.
    }
  }

  Future<void> _open(AppNotification n) async {
    switch (n.kind) {
      case NotificationKind.follow:
        openRiderProfile(context, n.actor);
      case NotificationKind.kudos:
        final rideId = n.rideId;
        final item = rideId == null
            ? null
            : await ref
                .read(rideRepositoryProvider)
                .feedItem(rideId)
                .catchError((Object _) => null);
        if (!mounted) return;
        if (item == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('That ride isn\'t available any more.')));
          return;
        }
        Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => RideDetailScreen(item: item)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);
    final list = state.value;
    final fresh = _new ?? const <String>{};
    final newOnes = list?.where((n) => fresh.contains(n.id)).toList();
    final earlier = list?.where((n) => !fresh.contains(n.id)).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Notifications', style: displayStyle(size: 20)),
      ),
      body: RefreshIndicator(
        onRefresh: () => refreshAll(ref, [notificationsProvider.future]),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (list == null && state.isLoading)
              for (var i = 0; i < 5; i++) const PersonRowSkeleton()
            else if (list == null)
              _message('Couldn\'t load notifications. Pull down to retry.')
            else if (list.isEmpty)
              _message('Nothing yet. When riders give kudos on your rides or '
                  'follow you, you\'ll see it here.')
            else ...[
              if (newOnes!.isNotEmpty) ...[
                const LabelMono('New', color: AppColors.primary),
                const SizedBox(height: 8),
                for (final n in newOnes) _row(n, isNew: true),
                const SizedBox(height: 16),
              ],
              if (earlier!.isNotEmpty) ...[
                if (newOnes.isNotEmpty) const LabelMono('Earlier'),
                if (newOnes.isNotEmpty) const SizedBox(height: 8),
                for (final n in earlier) _row(n, isNew: false),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(AppNotification n, {required bool isNew}) {
    final name = n.actor.displayName ?? n.actor.username ?? 'A rider';
    const bold = TextStyle(fontWeight: FontWeight.w600);
    final text = switch (n.kind) {
      NotificationKind.kudos => TextSpan(children: [
          TextSpan(text: name, style: bold),
          const TextSpan(text: ' gave kudos on '),
          n.rideTitle != null
              ? TextSpan(text: n.rideTitle, style: bold)
              : const TextSpan(text: 'your ride'),
        ]),
      NotificationKind.follow => TextSpan(children: [
          TextSpan(text: name, style: bold),
          const TextSpan(text: ' started following you'),
        ]),
    };
    return Padding(
      key: ValueKey(n.id),
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _open(n),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isNew ? AppColors.accent : AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isNew
                    ? AppColors.primary.withValues(alpha: 0.3)
                    : AppColors.border),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => openRiderProfile(context, n.actor),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    RiderAvatar(initials: n.actor.initials, size: 40),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: n.kind == NotificationKind.kudos
                              ? AppColors.primary
                              : AppColors.foreground,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.card, width: 2),
                        ),
                        child: Icon(
                          n.kind == NotificationKind.kudos
                              ? Icons.favorite
                              : Icons.person_add_alt_1,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(text,
                        style: const TextStyle(fontSize: 14, height: 1.3)),
                    const SizedBox(height: 2),
                    Text(timeAgo(n.createdAt.toLocal()),
                        style: monoStyle(size: 11, tracking: 0)),
                  ],
                ),
              ),
              if (n.kind == NotificationKind.follow) ...[
                const SizedBox(width: 8),
                FollowButton(
                    riderId: n.actor.id, followLabel: 'Follow back', width: 96),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(String text) => AppCard(
        padding: const EdgeInsets.all(16),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14, height: 1.4, color: AppColors.mutedForeground)),
      );
}
