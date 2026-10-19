import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'core.dart';
import 'live.dart';

/// The signed-in rider's notifications, newest first. New ones arrive live
/// (Realtime), so this reloads as they do.
final notificationsProvider =
    FutureProvider<List<AppNotification>>((ref) async {
  ref.watch(notificationsRevisionProvider);
  if (ref.watch(currentUserIdProvider) == null) return const [];
  return ref.watch(notificationRepositoryProvider).list();
});

/// How many notifications the rider hasn't seen, for the badge on Home.
final unreadNotificationCountProvider = FutureProvider<int>((ref) async {
  ref.watch(notificationsRevisionProvider);
  if (ref.watch(currentUserIdProvider) == null) return 0;
  return ref.watch(notificationRepositoryProvider).unreadCount();
});
