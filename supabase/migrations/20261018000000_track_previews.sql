-- Track previews. Ride lists (Discover, profiles, Activity) only draw a
-- small map of each ride, but used to download every ride's full GPS track
-- for it (tens to hundreds of KB each). Each track now also keeps a preview:
-- at most 200 of its points, positions only, to 5 decimals (~1 m):
-- {"v": 2, "p": [[lat, lng], ...]}. Lists load the preview; the ride's page
-- loads the full track.
-- The preview is made here, whenever a track is written, so the app never
-- sends it; existing tracks get theirs below. The app falls back to full
-- tracks while this hasn't been applied.
-- Requires 20261017000000_compact_tracks_bike_km.sql. Safe to re-run.

alter table public.ride_tracks add column if not exists preview jsonb;

comment on column public.ride_tracks.preview is
  'Up to 200 evenly spaced points of points, positions only: {"v":2,"p":[[lat,lng],...]}';

-- Up to [max_points] evenly spaced points of a track (either stored form),
-- always keeping the first and the last.
create or replace function public.ride_track_preview(
  points jsonb,
  max_points int default 200
)
returns jsonb
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
           row_number() over (order by i) as k
    from arr,
         jsonb_array_elements(
           case when jsonb_typeof(arr.a) = 'array' then arr.a else '[]'::jsonb end
         ) with ordinality as t (e, i)
    where (jsonb_typeof(e) = 'object' and e ? 'lat' and e ? 'lng')
       or (jsonb_typeof(e) = 'array' and jsonb_array_length(e) >= 2)
  ),
  n as (
    select count(*) as total,
           greatest(ceil(count(*)::numeric / greatest(max_points, 2))::bigint, 1)
             as step
    from p
  )
  select jsonb_build_object(
    'v', 2,
    'p', coalesce(
      jsonb_agg(
        jsonb_build_array(round(p.plat::numeric, 5), round(p.plng::numeric, 5))
        order by p.k
      ),
      '[]'::jsonb
    )
  )
  from p, n
  where (p.k - 1) % n.step = 0 or p.k = n.total;
$$;

create or replace function public.set_ride_track_preview()
returns trigger
language plpgsql
as $$
begin
  new.preview := public.ride_track_preview(new.points);
  return new;
end;
$$;

drop trigger if exists ride_tracks_set_preview on public.ride_tracks;
create trigger ride_tracks_set_preview
  before insert or update of points on public.ride_tracks
  for each row execute function public.set_ride_track_preview();

-- Tracks uploaded before previews.
update public.ride_tracks
set preview = public.ride_track_preview(points)
where preview is null;
