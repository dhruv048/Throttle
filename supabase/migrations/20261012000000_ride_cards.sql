-- Ride cards: the 4:5 ride image (bike photo + stats) a rider can post with a
-- ride, shown on the ride's page below its map and stats.
-- The image lives in a public Storage bucket under the rider's own folder
-- ("<user id>/<ride local id>.jpg"); the ride row points at it.
-- Safe to re-run.

alter table public.rides add column if not exists card_image_url text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'ride-cards',
  'ride-cards',
  true,
  5242880, -- 5 MB; the app uploads 1080×1350 JPEGs of a few hundred KB
  array['image/jpeg', 'image/png']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Public bucket: anyone can view via the public URL (file names are random
-- ride ids, so a private ride's card can't be guessed); writes are owner-only.
drop policy if exists "ride_cards_insert_own" on storage.objects;
create policy "ride_cards_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'ride-cards'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "ride_cards_update_own" on storage.objects;
create policy "ride_cards_update_own"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'ride-cards'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'ride-cards'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "ride_cards_delete_own" on storage.objects;
create policy "ride_cards_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'ride-cards'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Owners can read their own objects through the API (needed for upsert and
-- remove); everyone else uses the public URL.
drop policy if exists "ride_cards_select_own" on storage.objects;
create policy "ride_cards_select_own"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'ride-cards'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
