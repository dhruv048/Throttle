-- Feed support + hardening on top of 20251006000000_init.sql
-- Safe to re-run.

-- ---------------------------------------------------------------------------
-- Ride start / end place names for feed cards ("Kathmandu → Nagarkot")
-- ---------------------------------------------------------------------------

alter table public.rides add column if not exists start_place text;
alter table public.rides add column if not exists end_place text;

create index if not exists rides_visibility_created_at_idx
  on public.rides (visibility, created_at desc);

-- ---------------------------------------------------------------------------
-- kudos_count / comments_count are owned by the count triggers.
-- Direct client writes (trigger depth 1) are ignored; the bump_* triggers
-- update rides from inside another trigger (depth > 1) and pass through.
-- ---------------------------------------------------------------------------

create or replace function public.protect_ride_counts()
returns trigger
language plpgsql
as $$
begin
  if pg_trigger_depth() > 1 then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.kudos_count := 0;
    new.comments_count := 0;
  else
    new.kudos_count := old.kudos_count;
    new.comments_count := old.comments_count;
  end if;
  return new;
end;
$$;

drop trigger if exists rides_protect_counts on public.rides;
create trigger rides_protect_counts
  before insert or update on public.rides
  for each row execute function public.protect_ride_counts();

-- ---------------------------------------------------------------------------
-- Fix: lowercase *before* stripping, otherwise "Sam.Goyal" became "amoyal".
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  base_username text;
  candidate text;
  n int := 0;
begin
  base_username := regexp_replace(
    lower(coalesce(
      new.raw_user_meta_data->>'preferred_username',
      split_part(coalesce(new.email, 'rider'), '@', 1),
      'rider'
    )),
    '[^a-z0-9_]',
    '',
    'g'
  );

  if char_length(base_username) < 3 then
    base_username := 'rider';
  end if;
  base_username := left(base_username, 20);

  candidate := base_username;
  while exists (select 1 from public.profiles p where p.username = candidate) loop
    n := n + 1;
    candidate := left(base_username, 20 - char_length(n::text)) || n::text;
  end loop;

  insert into public.profiles (id, username, display_name, avatar_url, onboarding_completed)
  values (
    new.id,
    candidate,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', candidate),
    new.raw_user_meta_data->>'avatar_url',
    false
  )
  on conflict (id) do nothing;

  return new;
end;
$$;
