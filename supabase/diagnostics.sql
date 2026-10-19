-- Where the database's disk goes, and whether bike distances add up.
-- Paste into the Supabase SQL Editor and run one query at a time. Every
-- query here only reads, except the optional clean-up at the end.

-- 1. The database itself (tables, indexes, system catalogs), not counting
--    the write-ahead log. A new Supabase project already uses a few tens of
--    MB here before any app data.
select pg_size_pretty(pg_database_size(current_database())) as database_size;

-- 2. The biggest tables, all schemas (auth, storage, realtime, … included).
select n.nspname as schema,
       c.relname as table,
       pg_size_pretty(pg_total_relation_size(c.oid)) as total,
       pg_size_pretty(pg_relation_size(c.oid)) as rows,
       pg_size_pretty(pg_indexes_size(c.oid)) as indexes,
       pg_size_pretty(coalesce(pg_total_relation_size(c.reltoastrelid), 0)) as toast
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where c.relkind in ('r', 'm', 'p')
order by pg_total_relation_size(c.oid) desc
limit 20;

-- 3. The app's tables: how many rows, how big, how much is dead (rows
--    replaced or deleted, waiting for vacuum).
select relname as table,
       n_live_tup as live_rows,
       n_dead_tup as dead_rows,
       pg_size_pretty(pg_total_relation_size(relid)) as total,
       last_autovacuum
from pg_stat_user_tables
where schemaname = 'public'
order by pg_total_relation_size(relid) desc;

-- 4. GPS tracks: average size per ride, old and new format, and the
--    previews lists load instead (20261018000000_track_previews.sql).
select case when jsonb_typeof(points) = 'object' then 'v2 (compact)'
            else 'v1 (objects)' end as format,
       count(*) as tracks,
       pg_size_pretty(avg(pg_column_size(points))::bigint) as avg_size,
       pg_size_pretty(sum(pg_column_size(points))::bigint) as total_size,
       pg_size_pretty(avg(pg_column_size(preview))::bigint) as avg_preview
from public.ride_tracks
group by 1;

-- 5. The write-ahead log. Postgres keeps recent WAL on disk (on Supabase it
--    counts toward "Disk usage"), and keeps more while a replication slot
--    (Realtime) hasn't caught up. May need extra privileges; skip if it
--    errors.
select pg_size_pretty(sum(size)) as wal_size from pg_ls_waldir();

select slot_name,
       active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn))
         as wal_held_back
from pg_replication_slots;

-- 6. Bike distances: ridden_km should equal the sum of each bike's rides.
select b.name,
       b.ridden_km,
       coalesce(sum(r.distance_km), 0) as rides_km,
       count(r.id) as rides
from public.bikes b
left join public.rides r on r.bike_id = b.id and r.user_id = b.user_id
group by b.id
order by b.name;

-- Rides credited to no bike, and whether the distance triggers are there.
select count(*) as rides_without_bike from public.rides where bike_id is null;

select tgname as trigger, tgrelid::regclass as on_table, tgenabled
from pg_trigger
where tgname in ('rides_bike_km_ai', 'rides_bike_km_au', 'rides_bike_km_ad',
                 'bikes_protect_ridden_km', 'ride_tracks_set_flag');

-- 7. Optional clean-up: rewrites the app's busiest tables without their
--    dead rows, giving the space back. Takes a lock on each table for a
--    moment (fine at this size). Run each line on its own, outside a
--    transaction.
-- vacuum full public.ride_tracks;
-- vacuum full public.rides;
-- vacuum full public.notifications;
