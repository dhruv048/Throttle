-- Ride flags: every ride plants a flag at the furthest point it reached
-- from where it started (the far end of an out-and-back, the destination of
-- a one-way ride). A rider's profile shows all their flags on a map.
-- The point is worked out from the ride's track as it uploads (and here for
-- rides already uploaded), the same way as flagPoint() in
-- lib/models/models.dart. The app never writes it, so rides still upload if
-- this hasn't been applied yet.
-- Also: one journal row per uploaded file, so a photo queued on the phone
-- can't be added twice by a retried upload.
-- Safe to re-run.

alter table public.rides add column if not exists flag_lat double precision;
alter table public.rides add column if not exists flag_lng double precision;

create index if not exists rides_user_id_flag_idx
  on public.rides (user_id)
  where flag_lat is not null;

-- The point of a track (a JSON array of {lat, lng, …}) furthest from its
-- first point; nulls for an empty track.
create or replace function public.ride_flag_point(
  points jsonb,
  out lat double precision,
  out lng double precision
)
language sql
immutable
as $$
  with p as (
    select (e ->> 'lat')::double precision as plat,
           (e ->> 'lng')::double precision as plng,
           i
    from jsonb_array_elements(
           case when jsonb_typeof(points) = 'array' then points else '[]'::jsonb end
         ) with ordinality as t (e, i)
    where e ? 'lat' and e ? 'lng'
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

create or replace function public.set_ride_flag()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  f record;
begin
  select * into f from public.ride_flag_point(new.points);
  update public.rides
  set flag_lat = f.lat, flag_lng = f.lng
  where id = new.ride_id;
  return new;
end;
$$;

drop trigger if exists ride_tracks_set_flag on public.ride_tracks;
create trigger ride_tracks_set_flag
  after insert or update of points on public.ride_tracks
  for each row execute function public.set_ride_flag();

-- Rides uploaded before flags.
update public.rides r
set flag_lat = f.lat, flag_lng = f.lng
from public.ride_tracks t
cross join lateral public.ride_flag_point(t.points) f
where t.ride_id = r.id
  and r.flag_lat is null
  and f.lat is not null;

-- ---------------------------------------------------------------------------
-- Ride Journal: a file is in a journal once.
-- ---------------------------------------------------------------------------

create unique index if not exists ride_media_storage_path_key
  on public.ride_media (storage_path);
