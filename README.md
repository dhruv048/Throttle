# Throttle (Flutter)

Motorcycle social feed: ride, record, share — backed by Supabase.

## First-time setup

```bash
flutter pub get
```

### Supabase

1. Create a project at [supabase.com](https://supabase.com/dashboard)
2. Run both SQL files in `supabase/migrations/` in order, then `supabase/seed.sql` for demo rides (see `supabase/README.md`)
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
| Login / onboarding | `lib/screens/auth/` |

**SHARE RIDE** writes to a local JSON queue first (`LocalRideStore`), then uploads `rides` + `ride_tracks`. `RideSyncService` retries on launch, sign-in and whenever connectivity returns. Uploads are idempotent via `rides.local_id`, so a retry never duplicates a ride.

## What’s included

- Google sign-in → auto profile (`handle_new_user` trigger) → onboarding (username + first bike)
- Ride visibility RLS: public / followers / private; owner-only edit/delete
- Kudos & comment count triggers
- Home feed and Activity read live rides; every ride card shows its GPS track on an OpenStreetMap map, tap for details
- Activity: year totals, weekly km, monthly challenge and all your rides (including ones still waiting to sync)
- Per-bike km: a DB trigger credits each ride's distance to its bike (`bikes.ridden_km`)
- Distance: `RideTracker` (`lib/services/ride_tracker.dart`) filters GPS jitter/glitches, uses Doppler speed, and keeps recording with the screen off
- Record: pick your motorcycle (photo cards), then a live map follows you and draws the track, with speed/distance/time/avg overlaid
- FINISH auto-saves the ride to your profile (device first, then cloud); rides under 50 m aren't auto-saved
- Share a ride as a 1080×1350 image (bike photo, your own photo, route map or plain background) via the OS share sheet
- Bike photos: add/change when adding or editing a bike (Profile → tap a bike), stored in Supabase Storage
- Discover and the home "Nearby"/group-ride cards still use mock data from `lib/data.dart`
