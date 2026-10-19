-- In-app notifications: a rider hears when someone gives kudos on one of
-- their rides or starts following them. Rows are only ever written by the
-- triggers below; riders read their own, mark them read and delete them.
-- Streamed to the app through Supabase Realtime. Safe to re-run.

do $$ begin
  create type public.notification_kind as enum ('kudos', 'follow');
exception when duplicate_object then null;
end $$;

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  -- Who it's for.
  user_id uuid not null references public.profiles (id) on delete cascade,
  -- Who did it.
  actor_id uuid not null references public.profiles (id) on delete cascade,
  kind public.notification_kind not null,
  -- The ride, for kudos.
  ride_id uuid references public.rides (id) on delete cascade,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

-- One per rider, kind and ride: kudos tapped on and off doesn't stack up.
create unique index if not exists notifications_once_uidx
  on public.notifications (user_id, actor_id, kind, ride_id) nulls not distinct;

-- ---------------------------------------------------------------------------
-- Triggers: kudos and follows notify; taking them back removes the
-- notification again.
-- ---------------------------------------------------------------------------

create or replace function public.notify_kudos()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid;
begin
  if tg_op = 'INSERT' then
    select r.user_id into owner from public.rides r where r.id = new.ride_id;
    -- Kudos on your own ride isn't news.
    if owner is not null and owner <> new.user_id then
      insert into public.notifications (user_id, actor_id, kind, ride_id)
      values (owner, new.user_id, 'kudos', new.ride_id)
      on conflict do nothing;
    end if;
    return new;
  end if;
  delete from public.notifications n
  where n.kind = 'kudos'
    and n.actor_id = old.user_id
    and n.ride_id = old.ride_id;
  return old;
end;
$$;

drop trigger if exists kudos_notify_ai on public.kudos;
create trigger kudos_notify_ai
  after insert on public.kudos
  for each row execute function public.notify_kudos();

drop trigger if exists kudos_notify_ad on public.kudos;
create trigger kudos_notify_ad
  after delete on public.kudos
  for each row execute function public.notify_kudos();

create or replace function public.notify_follow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.notifications (user_id, actor_id, kind)
    values (new.following_id, new.follower_id, 'follow')
    on conflict do nothing;
    return new;
  end if;
  delete from public.notifications n
  where n.kind = 'follow'
    and n.user_id = old.following_id
    and n.actor_id = old.follower_id;
  return old;
end;
$$;

drop trigger if exists follows_notify_ai on public.follows;
create trigger follows_notify_ai
  after insert on public.follows
  for each row execute function public.notify_follow();

drop trigger if exists follows_notify_ad on public.follows;
create trigger follows_notify_ad
  after delete on public.follows
  for each row execute function public.notify_follow();

-- ---------------------------------------------------------------------------
-- RLS: your own notifications only. The app may only change read_at.
-- ---------------------------------------------------------------------------

alter table public.notifications enable row level security;

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
  on public.notifications for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own"
  on public.notifications for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "notifications_delete_own" on public.notifications;
create policy "notifications_delete_own"
  on public.notifications for delete
  to authenticated
  using (user_id = auth.uid());

revoke insert, update on public.notifications from anon, authenticated;
grant select, delete on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime: new notifications reach the app as they happen.
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end
$$;
