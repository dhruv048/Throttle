-- Per-bike distance: every ride's distance is credited to its bike.
-- Safe to re-run.

alter table public.bikes add column if not exists ridden_km numeric(12, 3) not null default 0;

-- Credit/debit a bike when rides are added, removed, re-assigned or edited.
-- Also bumps odometer_km so the odometer keeps counting up as you ride.
-- Only credits bikes owned by the ride's rider (bike_id isn't checked by RLS).
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

-- Backfill from rides recorded before this migration. Idempotent: recomputes
-- ridden_km from scratch and moves odometer_km by the same correction.
-- Runs before the write guard below exists (dropped first on re-runs).
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

-- ridden_km is owned by the trigger above; ignore direct client writes.
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
