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

Both are safe to re-run.

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
| `rides` | Ride metadata + visibility |
| `ride_tracks` | GPS polyline JSON |
| `follows` | Social graph |
| `kudos` | Likes (bumps `rides.kudos_count`) |
| `comments` | Comments (bumps `rides.comments_count`) |
