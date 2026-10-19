# Throttle (Flutter)

Motorcycle social feed: ride, record, share — backed by Supabase.

## First-time setup

```bash
flutter pub get
```

### Supabase

1. Create a project at [supabase.com](https://supabase.com/dashboard)
2. Run the SQL files in `supabase/migrations/` in order, then `supabase/seed.sql` for demo rides (see `supabase/README.md`)
3. Enable **Google** under Authentication → Providers
4. Add redirect URL: `com.wheelsclub.app://login-callback`
5. Pass credentials when running:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY \
  --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

### Location permissions

Already configured for Android (`ACCESS_FINE_LOCATION`) and iOS (`NSLocationWhenInUseUsageDescription`).

## Architecture

| Layer | Path |
|-------|------|
| Schema / RLS / triggers | `supabase/migrations/` |
| Models | `lib/models/` |
| Repositories | `lib/repositories/` |
| Auth + offline sync | `lib/services/` |
| App state (Riverpod) | `lib/providers/` |
| Live updates | `lib/services/data_changes.dart`, `realtime_service.dart`, `lib/providers/live.dart` |
| Loading skeletons | `lib/widgets/skeleton.dart` |
| Login / onboarding | `lib/screens/auth/` |

**State:** [Riverpod](https://riverpod.dev) (`flutter_riverpod`, no code generation). Repositories and services stay plain classes; `lib/providers/` wires them up and holds the app's state: the session (`currentUserIdProvider`, which every rider's data watches, so it starts over on sign-in/out), the rider's profile, bikes, follows and rides, the feeds, the current tab, and the ride being recorded (`rideRecorderProvider`, `finishedRideProvider`). Screens are `ConsumerWidget`s that watch those; only short-lived UI state (text fields, busy flags, the ride card design) stays in `setState`.

Data layer classes report what they change through `DataChanges` (our own writes immediately; `RealtimeService` for changes made anywhere else). `AppDataChanges` bumps a revision provider that the affected providers watch, so they reload, or patches per-ride state in place (live kudos/comment counts, deleted rides). Tabs refresh when they come on screen and when the app returns from the background, keeping the current data on screen until the new data arrives. Until data has loaded, screens show skeletons, never placeholder values. Riverpod's automatic retry is off (`noRetry`): screens say what failed and reload on pull-to-refresh.

**SAVE RIDE** writes to a local JSON queue first (`LocalRideStore`), then uploads the ride card (if attached, to the `ride-cards` bucket), `rides` and `ride_tracks`. Until the rider decides, a finished ride waits on the phone as a draft that's never uploaded by itself. `RideSyncService` retries on launch, sign-in and whenever connectivity returns. Uploads are idempotent via `rides.local_id`, so a retry never duplicates a ride.

## What’s included

- Google sign-in → auto profile (`handle_new_user` trigger) → onboarding (username + first bike)
- Ride visibility RLS: public / followers / private; owner-only edit/delete
- Kudos & comment count triggers
- Home feed and Activity read live rides; every ride card shows its GPS track on an OpenStreetMap map, tap for details
- Activity: year totals, weekly km, monthly challenge and all your rides (including ones still waiting to sync)
- Per-bike km: a DB trigger credits each ride's distance to its bike (`bikes.ridden_km`)
- Distance: `RideTracker` (`lib/services/ride_tracker.dart`) filters GPS jitter/glitches, uses Doppler speed, and keeps recording with the screen off
- Record: pick your motorcycle (photo cards), then a live map follows you and draws the track, with speed/distance/time/avg overlaid
- After FINISH the ride is kept on the phone (so closing the app doesn't lose it) until you decide: who can see it (public / followers / private), whether to post its ride card with it, then SAVE RIDE (device first, then cloud), Share or Discard
- Share a ride as a 1080×1350 image (bike photo, your own photo, route map or plain background) via the OS share sheet; the same ride card can be posted with the ride and shows on its page below the map and stats
- Bike photos: add/change when adding or editing a bike (Profile → tap a bike), stored in Supabase Storage
- Discover: popular public rides of the last 30 days, rider search and real follow/unfollow
