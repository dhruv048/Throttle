-- Bike photos: a URL on the bike + a public Storage bucket where each rider
-- can only write inside their own folder ("<user id>/<file>").
-- Safe to re-run.

alter table public.bikes add column if not exists photo_url text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'bike-photos',
  'bike-photos',
  true,
  5242880, -- 5 MB; the app uploads ~1600px JPEGs well under this
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Public bucket: anyone can view via the public URL; writes are owner-only.
drop policy if exists "bike_photos_insert_own" on storage.objects;
create policy "bike_photos_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'bike-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "bike_photos_update_own" on storage.objects;
create policy "bike_photos_update_own"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'bike-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'bike-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "bike_photos_delete_own" on storage.objects;
create policy "bike_photos_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'bike-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Owners can list/read their own objects through the API (needed for
-- upsert/remove); everyone else uses the public URL.
drop policy if exists "bike_photos_select_own" on storage.objects;
create policy "bike_photos_select_own"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'bike-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
