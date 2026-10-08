-- Throttle / WheelsClub schema, RLS, triggers
-- Apply in Supabase SQL Editor or via `supabase db push`

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.ride_visibility as enum ('public', 'followers', 'private');
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text unique,
  display_name text,
  avatar_url text,
  city text,
  bio text,
  onboarding_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint username_format check (
    username is null
    or (char_length(username) between 3 and 24 and username ~ '^[a-z0-9_]+$')
  )
);

create table if not exists public.bikes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  make text,
  model text,
  year int,
  odometer_km numeric(12, 1) not null default 0,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists bikes_user_id_idx on public.bikes (user_id);

create table if not exists public.rides (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  bike_id uuid references public.bikes (id) on delete set null,
  title text not null default 'Ride',
  visibility public.ride_visibility not null default 'followers',
  distance_km numeric(12, 3) not null default 0,
  moving_time_secs int not null default 0,
  avg_speed_kmh numeric(8, 2) not null default 0,
  max_speed_kmh numeric(8, 2) not null default 0,
  elevation_m numeric(10, 1) not null default 0,
  started_at timestamptz,
  ended_at timestamptz,
  kudos_count int not null default 0,
  comments_count int not null default 0,
  local_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists rides_user_id_idx on public.rides (user_id);
create index if not exists rides_created_at_idx on public.rides (created_at desc);
create unique index if not exists rides_user_local_id_uidx
  on public.rides (user_id, local_id)
  where local_id is not null;

create table if not exists public.ride_tracks (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null unique references public.rides (id) on delete cascade,
  -- [{lat, lng, t?, elev?, accuracy?}, ...]
  points jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  following_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint follows_no_self check (follower_id <> following_id)
);

create index if not exists follows_following_id_idx on public.follows (following_id);

create table if not exists public.kudos (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (ride_id, user_id)
);

create index if not exists kudos_ride_id_idx on public.kudos (ride_id);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint comments_body_len check (char_length(body) between 1 and 2000)
);

create index if not exists comments_ride_id_idx on public.comments (ride_id);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.is_following(viewer uuid, owner uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.follows f
    where f.follower_id = viewer
      and f.following_id = owner
  );
$$;

create or replace function public.can_view_ride(r public.rides)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    r.user_id = auth.uid()
    or r.visibility = 'public'
    or (
      r.visibility = 'followers'
      and public.is_following(auth.uid(), r.user_id)
    );
$$;

-- Soft single-primary: when a bike is marked primary, clear others for user
create or replace function public.ensure_single_primary_bike()
returns trigger
language plpgsql
as $$
begin
  if new.is_primary then
    update public.bikes
    set is_primary = false
    where user_id = new.user_id
      and id <> new.id
      and is_primary = true;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Auto-create profile on signup
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
  base_username := lower(regexp_replace(
    coalesce(
      new.raw_user_meta_data->>'preferred_username',
      split_part(coalesce(new.email, 'rider'), '@', 1),
      'rider'
    ),
    '[^a-z0-9_]',
    '',
    'g'
  ));

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

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Kudos / comments count triggers
-- ---------------------------------------------------------------------------

create or replace function public.bump_kudos_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.rides set kudos_count = kudos_count + 1 where id = new.ride_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.rides set kudos_count = greatest(kudos_count - 1, 0) where id = old.ride_id;
    return old;
  end if;
  return null;
end;
$$;

create or replace function public.bump_comments_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.rides set comments_count = comments_count + 1 where id = new.ride_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.rides set comments_count = greatest(comments_count - 1, 0) where id = old.ride_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

drop trigger if exists bikes_set_updated_at on public.bikes;
create trigger bikes_set_updated_at
  before update on public.bikes
  for each row execute function public.set_updated_at();

drop trigger if exists bikes_ensure_primary on public.bikes;
create trigger bikes_ensure_primary
  before insert or update of is_primary on public.bikes
  for each row execute function public.ensure_single_primary_bike();

drop trigger if exists rides_set_updated_at on public.rides;
create trigger rides_set_updated_at
  before update on public.rides
  for each row execute function public.set_updated_at();

drop trigger if exists comments_set_updated_at on public.comments;
create trigger comments_set_updated_at
  before update on public.comments
  for each row execute function public.set_updated_at();

drop trigger if exists kudos_count_ai on public.kudos;
create trigger kudos_count_ai
  after insert on public.kudos
  for each row execute function public.bump_kudos_count();

drop trigger if exists kudos_count_ad on public.kudos;
create trigger kudos_count_ad
  after delete on public.kudos
  for each row execute function public.bump_kudos_count();

drop trigger if exists comments_count_ai on public.comments;
create trigger comments_count_ai
  after insert on public.comments
  for each row execute function public.bump_comments_count();

drop trigger if exists comments_count_ad on public.comments;
create trigger comments_count_ad
  after delete on public.comments
  for each row execute function public.bump_comments_count();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.bikes enable row level security;
alter table public.rides enable row level security;
alter table public.ride_tracks enable row level security;
alter table public.follows enable row level security;
alter table public.kudos enable row level security;
alter table public.comments enable row level security;

-- profiles
drop policy if exists "profiles_select_all" on public.profiles;
create policy "profiles_select_all"
  on public.profiles for select
  to authenticated, anon
  using (true);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert
  to authenticated
  with check (id = auth.uid());

-- bikes
drop policy if exists "bikes_select_visible" on public.bikes;
create policy "bikes_select_visible"
  on public.bikes for select
  to authenticated, anon
  using (true);

drop policy if exists "bikes_insert_own" on public.bikes;
create policy "bikes_insert_own"
  on public.bikes for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "bikes_update_own" on public.bikes;
create policy "bikes_update_own"
  on public.bikes for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "bikes_delete_own" on public.bikes;
create policy "bikes_delete_own"
  on public.bikes for delete
  to authenticated
  using (user_id = auth.uid());

-- rides: visibility-aware read; owner-only write/delete
drop policy if exists "rides_select_visible" on public.rides;
create policy "rides_select_visible"
  on public.rides for select
  to authenticated, anon
  using (public.can_view_ride(rides));

drop policy if exists "rides_insert_own" on public.rides;
create policy "rides_insert_own"
  on public.rides for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "rides_update_own" on public.rides;
create policy "rides_update_own"
  on public.rides for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "rides_delete_own" on public.rides;
create policy "rides_delete_own"
  on public.rides for delete
  to authenticated
  using (user_id = auth.uid());

-- ride_tracks follow ride visibility
drop policy if exists "ride_tracks_select_visible" on public.ride_tracks;
create policy "ride_tracks_select_visible"
  on public.ride_tracks for select
  to authenticated, anon
  using (
    exists (
      select 1 from public.rides r
      where r.id = ride_tracks.ride_id
        and public.can_view_ride(r)
    )
  );

drop policy if exists "ride_tracks_insert_own" on public.ride_tracks;
create policy "ride_tracks_insert_own"
  on public.ride_tracks for insert
  to authenticated
  with check (
    exists (
      select 1 from public.rides r
      where r.id = ride_id and r.user_id = auth.uid()
    )
  );

drop policy if exists "ride_tracks_update_own" on public.ride_tracks;
create policy "ride_tracks_update_own"
  on public.ride_tracks for update
  to authenticated
  using (
    exists (
      select 1 from public.rides r
      where r.id = ride_tracks.ride_id and r.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.rides r
      where r.id = ride_id and r.user_id = auth.uid()
    )
  );

drop policy if exists "ride_tracks_delete_own" on public.ride_tracks;
create policy "ride_tracks_delete_own"
  on public.ride_tracks for delete
  to authenticated
  using (
    exists (
      select 1 from public.rides r
      where r.id = ride_tracks.ride_id and r.user_id = auth.uid()
    )
  );

-- follows
drop policy if exists "follows_select_all" on public.follows;
create policy "follows_select_all"
  on public.follows for select
  to authenticated, anon
  using (true);

drop policy if exists "follows_insert_own" on public.follows;
create policy "follows_insert_own"
  on public.follows for insert
  to authenticated
  with check (follower_id = auth.uid());

drop policy if exists "follows_delete_own" on public.follows;
create policy "follows_delete_own"
  on public.follows for delete
  to authenticated
  using (follower_id = auth.uid());

-- kudos: readable if ride visible; insert/delete own
drop policy if exists "kudos_select_visible" on public.kudos;
create policy "kudos_select_visible"
  on public.kudos for select
  to authenticated, anon
  using (
    exists (
      select 1 from public.rides r
      where r.id = kudos.ride_id and public.can_view_ride(r)
    )
  );

drop policy if exists "kudos_insert_own" on public.kudos;
create policy "kudos_insert_own"
  on public.kudos for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.rides r
      where r.id = ride_id and public.can_view_ride(r)
    )
  );

drop policy if exists "kudos_delete_own" on public.kudos;
create policy "kudos_delete_own"
  on public.kudos for delete
  to authenticated
  using (user_id = auth.uid());

-- comments
drop policy if exists "comments_select_visible" on public.comments;
create policy "comments_select_visible"
  on public.comments for select
  to authenticated, anon
  using (
    exists (
      select 1 from public.rides r
      where r.id = comments.ride_id and public.can_view_ride(r)
    )
  );

drop policy if exists "comments_insert_own" on public.comments;
create policy "comments_insert_own"
  on public.comments for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.rides r
      where r.id = ride_id and public.can_view_ride(r)
    )
  );

drop policy if exists "comments_update_own" on public.comments;
create policy "comments_update_own"
  on public.comments for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "comments_delete_own" on public.comments;
create policy "comments_delete_own"
  on public.comments for delete
  to authenticated
  using (user_id = auth.uid());
