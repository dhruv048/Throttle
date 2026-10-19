-- 1. Compact tracks. The app now stores a ride's track as
--    {"v": 2, "t0": <time of the first fix>, "p": [[lat, lng, dt, elev], ...]}
--    (dt: seconds since t0) instead of a list of {lat, lng, t, elev, accuracy}
--    objects: about a third of the size. Older tracks stay as they are; both
--    are read. ride_flag_point() learns the new form.
-- 2. Place names. rides.start_place and rides.end_place (from
--    20261008000000_feed_support.sql) now hold where a ride set off from and
--    where it reached (its flag), named by the app.
-- 3. Bike distance repair. Re-installs the triggers that credit each ride's
--    distance to its bike (20261009000000_bike_ridden_km.sql) and recomputes
--    every bike's ridden_km from its rides, in case they were missing or
--    out of step.
-- Requires 20261016000000_ride_flags.sql. Safe to re-run.

-- ---------------------------------------------------------------------------
-- 1. Flags from either track form
-- ---------------------------------------------------------------------------

create or replace function public.ride_flag_point(
  points jsonb,
  out lat double precision,
  out lng double precision
)
language sql
immutable
as $$
  with arr as (
    select case
             when jsonb_typeof(points) = 'object' then points -> 'p'
             else points
           end as a
  ),
  p as (
    select coalesce((e ->> 'lat')::double precision,
                    (e ->> 0)::double precision) as plat,
           coalesce((e ->> 'lng')::double precision,
                    (e ->> 1)::double precision) as plng,
           i
    from arr,
         jsonb_array_elements(
           case when jsonb_typeof(arr.a) = 'array' then arr.a else '[]'::jsonb end
         ) with ordinality as t (e, i)
    where (jsonb_typeof(e) = 'object' and e ? 'lat' and e ? 'lng')
       or (jsonb_typeof(e) = 'array' and jsonb_array_length(e) >= 2)
  ),
  s as (
    select plat as lat0, plng as lng0 from p order by i limit 1
  )
  select p.plat, p.plng
  from p, s
  -- Equirectangular: plenty to rank points within one ride.
  order by power((p.plng - s.lng0) * cos(radians(s.lat0)), 2)
           + power(p.plat - s.lat0, 2) desc,
           p.i
  limit 1;
$$;

comment on column public.ride_tracks.points is
  'v2: {"v":2,"t0":iso,"p":[[lat,lng,dt_s,elev_m],...]}; older rows: [{lat,lng,t,elev,accuracy},...]';
comment on column public.rides.end_place is
  'Where the ride reached: the place of its flag (the point furthest from its start)';

-- Flags for any ride that has a track but no flag yet.
update public.rides r
set flag_lat = f.lat, flag_lng = f.lng
from public.ride_tracks t
cross join lateral public.ride_flag_point(t.points) f
where t.ride_id = r.id
  and r.flag_lat is null
  and f.lat is not null;

-- ---------------------------------------------------------------------------
-- 3. Bike distance
-- ---------------------------------------------------------------------------

alter table public.bikes add column if not exists ridden_km numeric(12, 3) not null default 0;

create or replace function public.bump_bike_ridden_km()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') and old.bike_id is not null then
    update public.bikes
    set ridden_km = greatest(ridden_km - old.distance_km, 0),
        odometer_km = greatest(odometer_km - old.distance_km, 0)
    where id = old.bike_id and user_id = old.user_id;
  end if;
  if tg_op in ('INSERT', 'UPDATE') and new.bike_id is not null then
    update public.bikes
    set ridden_km = ridden_km + new.distance_km,
        odometer_km = odometer_km + new.distance_km
    where id = new.bike_id and user_id = new.user_id;
  end if;
  return null;
end;
$$;

drop trigger if exists rides_bike_km_ai on public.rides;
create trigger rides_bike_km_ai
  after insert on public.rides
  for each row execute function public.bump_bike_ridden_km();

drop trigger if exists rides_bike_km_au on public.rides;
create trigger rides_bike_km_au
  after update of bike_id, distance_km on public.rides
  for each row
  when (old.bike_id is distinct from new.bike_id or old.distance_km is distinct from new.distance_km)
  execute function public.bump_bike_ridden_km();

drop trigger if exists rides_bike_km_ad on public.rides;
create trigger rides_bike_km_ad
  after delete on public.rides
  for each row execute function public.bump_bike_ridden_km();

-- Recompute from the rides themselves (the guard below is dropped first so
-- this write goes through).
drop trigger if exists bikes_protect_ridden_km on public.bikes;

with totals as (
  select b.id, coalesce(sum(r.distance_km), 0) as km
  from public.bikes b
  left join public.rides r on r.bike_id = b.id and r.user_id = b.user_id
  group by b.id
)
update public.bikes b
set odometer_km = greatest(b.odometer_km + (t.km - b.ridden_km), 0),
    ridden_km = t.km
from totals t
where t.id = b.id and b.ridden_km is distinct from t.km;

-- Rides that were never credited to a bike go to the rider's primary one.
update public.rides r
set bike_id = (
  select b.id from public.bikes b
  where b.user_id = r.user_id
  order by b.is_primary desc, b.created_at
  limit 1
)
where r.bike_id is null
  and exists (select 1 from public.bikes b where b.user_id = r.user_id);

create or replace function public.protect_bike_ridden_km()
returns trigger
language plpgsql
as $$
begin
  if pg_trigger_depth() > 1 then
    return new;
  end if;
  new.ridden_km := case when tg_op = 'INSERT' then 0 else old.ridden_km end;
  return new;
end;
$$;

drop trigger if exists bikes_protect_ridden_km on public.bikes;
create trigger bikes_protect_ridden_km
  before insert or update on public.bikes
  for each row execute function public.protect_bike_ridden_km();
