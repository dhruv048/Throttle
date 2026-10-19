import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/bike_repository.dart';
import '../repositories/journal_repository.dart';
import '../repositories/notification_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/ride_repository.dart';
import '../services/auth_service.dart';
import '../services/local_ride_store.dart';
import '../services/place_names.dart';
import '../services/realtime_service.dart';
import '../services/ride_sync_service.dart';
import 'live.dart';

// The app's services and the signed-in session. Every other provider builds
// on these, so tests can swap any of them with an override.

/// Riverpod retries failing providers by default. Screens here say what
/// failed and reload on pull-to-refresh, tab switch and resume instead.
Duration? noRetry(int retryCount, Object error) => null;

final supabaseClientProvider =
    Provider<SupabaseClient>((ref) => Supabase.instance.client);

final localRideStoreProvider =
    Provider<LocalRideStore>((ref) => LocalRideStore());

/// Names places from coordinates (where rides set off from and reached).
final placeNamesProvider = Provider<PlaceNames>((ref) => PlaceNames());

final bikeRepositoryProvider = Provider<BikeRepository>(
  (ref) => BikeRepository(
    client: ref.watch(supabaseClientProvider),
    changes: ref.watch(dataChangesProvider),
  ),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(
    client: ref.watch(supabaseClientProvider),
    changes: ref.watch(dataChangesProvider),
  ),
);

final journalRepositoryProvider = Provider<JournalRepository>(
  (ref) => JournalRepository(client: ref.watch(supabaseClientProvider)),
);

final rideRepositoryProvider = Provider<RideRepository>(
  (ref) => RideRepository(
    client: ref.watch(supabaseClientProvider),
    store: ref.watch(localRideStoreProvider),
    bikes: ref.watch(bikeRepositoryProvider),
    journal: ref.watch(journalRepositoryProvider),
    changes: ref.watch(dataChangesProvider),
  ),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(
    client: ref.watch(supabaseClientProvider),
    changes: ref.watch(dataChangesProvider),
  ),
);

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(
    client: ref.watch(supabaseClientProvider),
    profiles: ref.watch(profileRepositoryProvider),
    bikes: ref.watch(bikeRepositoryProvider),
  ),
);

final rideSyncServiceProvider = Provider<RideSyncService>((ref) {
  final sync = RideSyncService(
    store: ref.watch(localRideStoreProvider),
    rides: ref.watch(rideRepositoryProvider),
    changes: ref.watch(dataChangesProvider),
  );
  ref.onDispose(sync.stop);
  return sync;
});

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final realtime = RealtimeService(
    client: ref.watch(supabaseClientProvider),
    changes: ref.watch(dataChangesProvider),
  );
  ref.onDispose(realtime.stop);
  return realtime;
});

/// Sign-ins, sign-outs and token refreshes.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseClientProvider).auth.onAuthStateChange,
);

/// The signed-in session; null when signed out, and when Supabase isn't set
/// up (widget tests).
final sessionProvider = Provider<Session?>((ref) {
  final SupabaseClient client;
  try {
    client = ref.watch(supabaseClientProvider);
  } catch (_) {
    return null; // Supabase not initialised (tests)
  }
  ref.watch(authStateProvider);
  return client.auth.currentSession;
});

/// The signed-in rider's id, or null. It only changes on sign-in and
/// sign-out, so everything holding a rider's data watches it and starts over
/// for the next rider.
final currentUserIdProvider =
    Provider<String?>((ref) => ref.watch(sessionProvider)?.user.id);
