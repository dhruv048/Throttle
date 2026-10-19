# Supabase setup (Throttle)

## 1. Create a project

1. Go to [https://supabase.com/dashboard](https://supabase.com/dashboard) → **New project**
2. Copy **Project URL** and **anon / publishable key** from **Settings → API**

## 2. Apply schema

In the dashboard **SQL Editor**, paste and run each migration in order:

1. `supabase/migrations/20251006000000_init.sql` — tables, RLS, triggers
2. `supabase/migrations/20261008000000_feed_support.sql` — `start_place`/`end_place`, count-forgery guard, username fix
3. `supabase/migrations/20261009000000_bike_ridden_km.sql` — per-bike `ridden_km` (trigger credits each ride's distance to its bike and odometer; backfills existing rides)
4. `supabase/migrations/20261010000000_bike_photos.sql` — `bikes.photo_url` + public `bike-photos` Storage bucket (5 MB, images only; riders can only write to their own `<user id>/` folder)
5. `supabase/migrations/20261011000000_realtime.sql` — streams `rides`, `bikes` and `follows` changes to the app (Supabase Realtime; RLS still applies per rider)
6. `supabase/migrations/20261012000000_ride_cards.sql` — `rides.card_image_url` + public `ride-cards` Storage bucket for the ride card a rider can post with a ride (5 MB, JPEG/PNG; riders can only write to their own `<user id>/` folder)
7. `supabase/migrations/20261013000000_notifications.sql` — `notifications` table: triggers on `kudos` and `follows` notify the rider (and remove the notification when the kudos/follow is taken back); riders read and mark their own; streamed via Realtime
8. `supabase/migrations/20261014000000_ride_journal.sql` — Ride Journal: `rides.journal` (the rider's own words) + `ride_media` (photos/videos pinned on the route; same visibility as the ride) + public `ride-media` Storage bucket (50 MB, images and MP4/MOV; riders can only write to their own `<user id>/` folder)
9. `supabase/migrations/20261016000000_ride_flags.sql` — ride flags: `rides.flag_lat`/`flag_lng`, the furthest point each ride reached from its start, set by a trigger when its track uploads (and backfilled for existing rides); shown on riders' profiles (Flags tab). Also makes `ride_media.storage_path` unique, so photos queued on the phone can't be added twice
10. `supabase/migrations/20261017000000_compact_tracks_bike_km.sql` — reads the app's compact track format (about a third of the size) when placing flags; `start_place`/`end_place` now hold where a ride set off from and reached (named by the app); re-installs the bike-distance triggers and recomputes every bike's `ridden_km` from its rides (rides credited to no bike go to the rider's primary bike)
11. `supabase/migrations/20261018000000_track_previews.sql` — `ride_tracks.preview`: up to 200 points of each track (positions only), made by a trigger whenever a track is written and backfilled for existing ones. Ride lists load only the preview; a ride's page loads its full track. Until this is applied the app loads full tracks in lists
12. `supabase/migrations/20261019000000_rider_leaderboard.sql` — `rider_leaderboard()`: each rider's totals (rides, km, longest ride, climb, places reached, longest ride time) for Discover's achievements. Runs as the caller, so it only counts rides the viewer may see

All are safe to re-run.

### Disk usage

`supabase/diagnostics.sql` shows where the database's space goes (tables,
GPS tracks old vs new format, the write-ahead log, Realtime's replication
slot) and checks that bike distances add up. On a new project most of the
reported disk is Postgres itself, its write-ahead log and Supabase's own
schemas, not ride data.

### Demo data (home feed)

Paste and run `supabase/seed.sql` in the SQL Editor. It creates 5 demo riders
(no password — nobody can sign in as them), their bikes, 9 rides around the
Kathmandu valley with GPS tracks, follows, kudos and comments. 7 rides are
public, 1 is followers-only and 1 is private, so the feed also demonstrates RLS.
Re-running is a no-op. To remove it:

```sql
delete from auth.users where id::text like 'd0000000-0000-4000-8000-%';
```

Or with the CLI:

```bash
npx supabase link --project-ref <your-ref>
npx supabase db push
npx supabase db push --include-seed   # also runs supabase/seed.sql
```

## 3. Enable Google Auth

1. Google Cloud Console → create OAuth clients (Web + Android / iOS)
2. Supabase → **Authentication → Providers → Google** → enable
3. Paste the **Web client ID** into Authorized Client IDs
4. Enable **Skip nonce check** (needed for iOS native sign-in)
5. **Authentication → URL Configuration** → add redirect:

```
com.wheelsclub.app://login-callback
```

## 4. Flutter env

Create `lib/config/env.dart` from the example (gitignored), or pass `--dart-define`:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=GOOGLE_WEB_CLIENT_ID=....apps.googleusercontent.com \
  --dart-define=GOOGLE_IOS_CLIENT_ID=....apps.googleusercontent.com
```

## Tables

| Table | Purpose |
|-------|---------|
| `profiles` | Rider profile (auto-created on signup) |
| `bikes` | Garage / primary bike |
| `rides` | Ride metadata + visibility (+ its flag: the furthest point it reached) |
| `ride_tracks` | GPS polyline JSON |
| `follows` | Social graph |
| `kudos` | Likes (bumps `rides.kudos_count`) |
| `comments` | Comments (bumps `rides.comments_count`) |
| `notifications` | Kudos / new-follower notifications (written by triggers) |
| `ride_media` | Ride Journal photos and videos, pinned on the route |
