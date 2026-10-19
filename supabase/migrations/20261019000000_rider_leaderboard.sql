-- Leaderboard: each rider's totals, for Discover's achievements (top
-- riders by badges earned, and who holds each record). The app turns the
-- totals into badges (lib/services/achievements.dart), the same way it does
-- for a rider's own Activity page.
-- Runs as the caller (security invoker), so row-level security applies:
-- totals only count rides the viewer may see (public ones, followers-only
-- ones of riders they follow, and their own). Private rides never show.
-- Safe to re-run.

create or replace function public.rider_leaderboard(max_riders int default 100)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  city text,
  rides bigint,
  total_km numeric,
  longest_km numeric,
  climb_m numeric,
  biggest_climb_m numeric,
  places bigint,
  longest_secs int
)
language sql
stable
security invoker
set search_path = public
as $$
  select p.id,
         p.username,
         p.display_name,
         p.avatar_url,
         p.city,
         count(r.id),
         coalesce(sum(r.distance_km), 0),
         coalesce(max(r.distance_km), 0),
         coalesce(sum(r.elevation_m), 0),
         coalesce(max(r.elevation_m), 0),
         count(distinct r.end_place),
         coalesce(max(r.moving_time_secs), 0)
  from public.rides r
  join public.profiles p on p.id = r.user_id
  group by p.id
  order by sum(r.distance_km) desc
  limit greatest(least(max_riders, 500), 1);
$$;

grant execute on function public.rider_leaderboard(int) to anon, authenticated;
