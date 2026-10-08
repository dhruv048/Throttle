-- Demo riders, bikes, rides + GPS tracks, follows, kudos and comments
-- for the home feed. Run in the Supabase SQL Editor (needs the postgres role
-- because it writes auth.users). Re-runnable: fixed UUIDs + on conflict.
--
-- Self-contained: no temp tables or pg_temp functions, so it works even when
-- the editor doesn't run every statement in the same session.
--
-- Demo accounts have no password and no identity, so nobody can sign in
-- as them. Remove everything with the block at the bottom of this file.

-- ---------------------------------------------------------------------------
-- Riders (handle_new_user creates the profiles)
-- ---------------------------------------------------------------------------

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000', v.id::uuid, 'authenticated', 'authenticated',
  v.email, '', now(),
  '{"provider":"email","providers":["email"],"demo":true}'::jsonb,
  jsonb_build_object('full_name', v.full_name, 'preferred_username', v.username),
  now() - interval '60 days', now(),
  '', '', '', ''
from (values
  ('d0000000-0000-4000-8000-000000000001', 'alex.demo@wheelsclub.app',   'Alex Shrestha', 'alex_rides'),
  ('d0000000-0000-4000-8000-000000000002', 'priya.demo@wheelsclub.app',  'Priya Gurung',  'priya_g'),
  ('d0000000-0000-4000-8000-000000000003', 'sanjay.demo@wheelsclub.app', 'Sanjay Tamang', 'sanjay_t'),
  ('d0000000-0000-4000-8000-000000000004', 'mira.demo@wheelsclub.app',   'Mira Rai',      'mira_rai'),
  ('d0000000-0000-4000-8000-000000000005', 'bikash.demo@wheelsclub.app', 'Bikash Lama',   'bikash_lama')
) as v (id, email, full_name, username)
on conflict (id) do nothing;

update public.profiles p
set city = v.city,
    bio = v.bio,
    onboarding_completed = true
from (values
  ('d0000000-0000-4000-8000-000000000001', 'Kathmandu', 'Sunday rides, momo stops.'),
  ('d0000000-0000-4000-8000-000000000002', 'Bhaktapur', 'Chasing sunrises on two wheels.'),
  ('d0000000-0000-4000-8000-000000000003', 'Kathmandu', 'Twisties > highways.'),
  ('d0000000-0000-4000-8000-000000000004', 'Lalitpur',  'Commuter by week, tourer by weekend.'),
  ('d0000000-0000-4000-8000-000000000005', 'Pokhara',   'Long hauls and dirt roads.')
) as v (id, city, bio)
where p.id = v.id::uuid;

-- ---------------------------------------------------------------------------
-- Bikes
-- ---------------------------------------------------------------------------

insert into public.bikes (id, user_id, name, make, model, year, odometer_km, is_primary)
values
  ('d1000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001', 'Royal Enfield Himalayan', 'Royal Enfield', 'Himalayan', 2021, 18420, true),
  ('d1000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000002', 'KTM 390 Duke',            'KTM',           '390 Duke',  2022,  9310, true),
  ('d1000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000003', 'Honda CB350',             'Honda',         'CB350',     2023,  8205, true),
  ('d1000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000004', 'Yamaha MT-15',            'Yamaha',        'MT-15',     2023,  5420, true),
  ('d1000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000005', 'BMW G 310 GS',            'BMW',           'G 310 GS',  2020, 12940, true)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Rides + tracks
-- ---------------------------------------------------------------------------

do $seed$
declare
  r record;
  w jsonb;
  legs int;
  per_leg constant int := 24;
  total int;
  started timestamptz;
  secs int;
  gain numeric;
  pts jsonb;
  a jsonb;
  b jsonb;
  f double precision;
  wiggle double precision;
  k int;
begin
  for r in
    select * from (values
  ('d2000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000001',
   'Namobuddha Sunday', 'public', 'Kathmandu', 'Namobuddha', 41.8, 5880, 78, interval '2 hours',
   '[[27.6945,85.3206,1310],[27.6789,85.3493,1300],[27.6800,85.3880,1320],[27.6710,85.4298,1340],[27.6440,85.4800,1450],[27.6298,85.5214,1500],[27.6200,85.5560,1550],[27.5960,85.5700,1650],[27.5733,85.5850,1750]]'),
  ('d2000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000002', 'd1000000-0000-4000-8000-000000000002',
   'Nagarkot sunrise run', 'public', 'Bhaktapur', 'Nagarkot', 22.4, 3120, 64, interval '5 hours',
   '[[27.6722,85.4280,1400],[27.6820,85.4380,1450],[27.6950,85.4470,1550],[27.7010,85.4600,1700],[27.7080,85.4850,1900],[27.7154,85.5200,2100]]'),
  ('d2000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000003', 'd1000000-0000-4000-8000-000000000003',
   'Kakani hairpins', 'public', 'Balaju', 'Kakani', 24.6, 3480, 58, interval '20 hours',
   '[[27.7340,85.3030,1330],[27.7450,85.2900,1400],[27.7580,85.2780,1550],[27.7700,85.2700,1700],[27.7900,85.2620,1900],[27.8100,85.2550,2050]]'),
  ('d2000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000004', 'd1000000-0000-4000-8000-000000000004',
   'Rajpath to Daman', 'public', 'Thankot', 'Daman', 62.0, 7500, 71, interval '1 day 4 hours',
   '[[27.6890,85.2050,1400],[27.7120,85.1600,1100],[27.7333,85.1167,950],[27.7000,85.1050,1300],[27.6730,85.1010,1800],[27.6470,85.0660,1750],[27.6250,85.0800,2100],[27.6070,85.0890,2300]]'),
  ('d2000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000005', 'd1000000-0000-4000-8000-000000000005',
   'Bandipur escape', 'public', 'Thankot', 'Bandipur', 143.0, 13800, 96, interval '2 days',
   '[[27.6890,85.2050,1400],[27.7333,85.1167,950],[27.8180,84.8370,350],[27.8550,84.5600,280],[27.9700,84.4100,400],[27.9360,84.4070,1000]]'),
  ('d2000000-0000-4000-8000-000000000006', 'd0000000-0000-4000-8000-000000000002', 'd1000000-0000-4000-8000-000000000002',
   'Godawari coffee loop', 'public', 'Lalitpur', 'Godawari', 14.8, 2460, 55, interval '2 days 6 hours',
   '[[27.6766,85.3150,1320],[27.6590,85.3240,1330],[27.6300,85.3450,1400],[27.6100,85.3650,1450],[27.5960,85.3810,1500]]'),
  ('d2000000-0000-4000-8000-000000000007', 'd0000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000001',
   'Sundarijal evening blast', 'public', 'Chabahil', 'Sundarijal', 15.2, 2040, 62, interval '3 days',
   '[[27.7170,85.3460,1300],[27.7380,85.3880,1320],[27.7550,85.4100,1380],[27.7700,85.4270,1450]]'),
  ('d2000000-0000-4000-8000-000000000008', 'd0000000-0000-4000-8000-000000000004', 'd1000000-0000-4000-8000-000000000004',
   'Dhulikhel tea stop', 'followers', 'Koteshwor', 'Dhulikhel', 30.1, 4320, 74, interval '4 days',
   '[[27.6789,85.3493,1300],[27.6800,85.3880,1320],[27.6710,85.4298,1340],[27.6298,85.5214,1500],[27.6200,85.5560,1550]]'),
  ('d2000000-0000-4000-8000-000000000009', 'd0000000-0000-4000-8000-000000000005', 'd1000000-0000-4000-8000-000000000005',
   'Parts run to Teku', 'private', 'Thamel', 'Teku', 3.4, 840, 38, interval '5 days',
   '[[27.7150,85.3123,1330],[27.7050,85.3080,1320],[27.6950,85.3060,1310]]')
    ) as d (id, user_id, bike_id, title, visibility, start_place, end_place,
            distance_km, moving_time_secs, max_speed_kmh, ago, waypoints)
  loop
    w := r.waypoints::jsonb;
    legs := jsonb_array_length(w) - 1;

    -- Elevation gain: sum of climbs between waypoints.
    gain := 0;
    for i in 0 .. legs - 1 loop
      gain := gain + greatest((w->(i + 1)->>2)::numeric - (w->i->>2)::numeric, 0);
    end loop;

    insert into public.rides (
      id, user_id, bike_id, title, visibility, start_place, end_place,
      distance_km, moving_time_secs, avg_speed_kmh, max_speed_kmh, elevation_m,
      started_at, ended_at, created_at
    ) values (
      r.id::uuid, r.user_id::uuid, r.bike_id::uuid, r.title,
      r.visibility::public.ride_visibility, r.start_place, r.end_place,
      r.distance_km, r.moving_time_secs,
      round(r.distance_km / (r.moving_time_secs / 3600.0), 1),
      r.max_speed_kmh, gain,
      now() - r.ago - make_interval(secs => r.moving_time_secs),
      now() - r.ago,
      now() - r.ago
    )
    on conflict (id) do nothing;

    -- Use the stored start time so a re-run lines up with the existing ride.
    select x.started_at, x.moving_time_secs into started, secs
    from public.rides x where x.id = r.id::uuid;

    -- Densify waypoints [[lat, lng, elev], ...] into a timestamped GPS track,
    -- with small bends so the line reads like a road, not a ruler.
    total := legs * per_leg;
    pts := '[]'::jsonb;
    k := 0;
    for i in 0 .. legs - 1 loop
      a := w -> i;
      b := w -> (i + 1);
      for j in 0 .. per_leg - 1 loop
        f := j::double precision / per_leg;
        wiggle := sin(f * pi() * 2 + i) * 0.0012;
        pts := pts || jsonb_build_array(jsonb_build_object(
          'lat', round(((a->>0)::numeric + ((b->>0)::numeric - (a->>0)::numeric) * f::numeric + wiggle::numeric), 6),
          'lng', round(((a->>1)::numeric + ((b->>1)::numeric - (a->>1)::numeric) * f::numeric - wiggle::numeric), 6),
          'elev', round((a->>2)::numeric + ((b->>2)::numeric - (a->>2)::numeric) * f::numeric, 1),
          't', to_char((started + make_interval(secs => secs * k::double precision / total)) at time zone 'UTC',
                       'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        ));
        k := k + 1;
      end loop;
    end loop;
    b := w -> legs;
    pts := pts || jsonb_build_array(jsonb_build_object(
      'lat', (b->>0)::numeric,
      'lng', (b->>1)::numeric,
      'elev', (b->>2)::numeric,
      't', to_char((started + make_interval(secs => secs)) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
    ));

    insert into public.ride_tracks (ride_id, points)
    values (r.id::uuid, pts)
    on conflict (ride_id) do nothing;
  end loop;
end
$seed$;

-- ---------------------------------------------------------------------------
-- Social graph, kudos, comments (counts come from the triggers)
-- ---------------------------------------------------------------------------

insert into public.follows (follower_id, following_id)
values
  ('d0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000002'),
  ('d0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000004'),
  ('d0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001'),
  ('d0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000003'),
  ('d0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000001'),
  ('d0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000005'),
  ('d0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000002'),
  ('d0000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000001'),
  ('d0000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000004')
on conflict do nothing;

insert into public.kudos (ride_id, user_id)
select ('d2000000-0000-4000-8000-00000000000' || r)::uuid,
       ('d0000000-0000-4000-8000-00000000000' || u)::uuid
from (values
  (1, 2), (1, 3), (1, 4), (1, 5),
  (2, 1), (2, 3), (2, 4), (2, 5),
  (3, 1), (3, 2), (3, 5),
  (4, 1), (4, 2), (4, 3),
  (5, 1), (5, 3), (5, 4),
  (6, 1), (6, 4),
  (7, 2), (7, 5),
  (8, 2)
) as k (r, u)
on conflict (ride_id, user_id) do nothing;

insert into public.comments (id, ride_id, user_id, body, created_at)
values
  ('d3000000-0000-4000-8000-000000000001', 'd2000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000002', 'That climb after Dhulikhel is brutal. Nice pace!', now() - interval '90 minutes'),
  ('d3000000-0000-4000-8000-000000000002', 'd2000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000005', 'Monastery stop for tea?', now() - interval '80 minutes'),
  ('d3000000-0000-4000-8000-000000000003', 'd2000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001', 'Clouds cleared in time?', now() - interval '4 hours'),
  ('d3000000-0000-4000-8000-000000000004', 'd2000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000002', 'Full Langtang view. Worth the 5am alarm.', now() - interval '230 minutes'),
  ('d3000000-0000-4000-8000-000000000005', 'd2000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000003', 'Rajpath on an MT-15, respect.', now() - interval '1 day'),
  ('d3000000-0000-4000-8000-000000000006', 'd2000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000001', 'How was the Mugling stretch?', now() - interval '40 hours'),
  ('d3000000-0000-4000-8000-000000000007', 'd2000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000005', 'Dusty but fine after Malekhu.', now() - interval '39 hours')
on conflict (id) do nothing;


-- ---------------------------------------------------------------------------
-- To remove all demo data (cascades through profiles → bikes/rides/…):
--
--   delete from auth.users where id::text like 'd0000000-0000-4000-8000-%';
-- ---------------------------------------------------------------------------
