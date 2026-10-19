-- Ride Journal: a ride told as a story — photos and videos pinned to where
-- they happened on the route, each with a caption, plus the rider's own
-- words about the ride.
-- Files live in a public Storage bucket under the rider's own folder
-- ("<user id>/<ride id>/<random>.<ext>"); rows point at them and follow the
-- ride's visibility. Safe to re-run.

alter table public.rides add column if not exists journal text;

do $$ begin
  alter table public.rides
    add constraint rides_journal_len check (char_length(journal) <= 5000);
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.ride_media_kind as enum ('photo', 'video');
exception when duplicate_object then null;
end $$;

create table if not exists public.ride_media (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind public.ride_media_kind not null,
  url text not null,
  storage_path text not null,
  caption text,
  -- Where on the route it was taken (null: not placed).
  lat double precision,
  lng double precision,
  taken_at timestamptz,
  created_at timestamptz not null default now(),
  constraint ride_media_caption_len check (char_length(caption) <= 500)
);

create index if not exists ride_media_ride_id_idx on public.ride_media (ride_id);

alter table public.ride_media enable row level security;

-- Seen by whoever can see the ride.
drop policy if exists "ride_media_select_visible" on public.ride_media;
create policy "ride_media_select_visible"
  on public.ride_media for select
  to authenticated, anon
  using (
    exists (
      select 1 from public.rides r
      where r.id = ride_media.ride_id and public.can_view_ride(r)
    )
  );

-- Only on your own rides.
drop policy if exists "ride_media_insert_own" on public.ride_media;
create policy "ride_media_insert_own"
  on public.ride_media for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.rides r
      where r.id = ride_id and r.user_id = auth.uid()
    )
  );

drop policy if exists "ride_media_update_own" on public.ride_media;
create policy "ride_media_update_own"
  on public.ride_media for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "ride_media_delete_own" on public.ride_media;
create policy "ride_media_delete_own"
  on public.ride_media for delete
  to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'ride-media',
  'ride-media',
  true,
  52428800, -- 50 MB: photos are ~1600px JPEGs; videos are the big ones
  array['image/jpeg', 'image/png', 'image/heic', 'image/webp',
        'video/mp4', 'video/quicktime']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Public bucket: anyone can view via the public URL (paths are random, so a
-- private ride's media can't be guessed); writes are owner-only.
drop policy if exists "ride_media_files_insert_own" on storage.objects;
create policy "ride_media_files_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'ride-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "ride_media_files_update_own" on storage.objects;
create policy "ride_media_files_update_own"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'ride-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'ride-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "ride_media_files_delete_own" on storage.objects;
create policy "ride_media_files_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'ride-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "ride_media_files_select_own" on storage.objects;
create policy "ride_media_files_select_own"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'ride-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
