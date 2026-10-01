-- ============================================================================
-- Resim deposu: ImgBB yerine Supabase Storage.
--
-- Tek herkese açık bucket `media`, klasörler:
--   leagues/  teams/  players/  news/  matches/
-- Okuma herkese açık (public bucket, CDN linki). Yazma:
--   - admin ve turnuva sahipleri: tüm klasörler
--   - takım sorumluları: sadece players/
-- Silme: dosyayı yükleyen kullanıcı ya da admin.
-- Kayıtların kendisi (teams.logo_url vb.) zaten tablo RLS'i ile korunuyor;
-- buradaki kurallar yalnızca dosya yüklemeyi sınırlar.
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'media',
  'media',
  true,
  5 * 1024 * 1024,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.can_upload_media(p_folder text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    p_folder in ('leagues', 'teams', 'players', 'news', 'matches')
    and (
      public.is_admin()
      or public.is_any_league_owner()
      or (
        p_folder = 'players'
        and exists (select 1 from public.team_managers where user_id = auth.uid())
      )
    )
$$;

drop policy if exists "media insert" on storage.objects;
create policy "media insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'media'
    and public.can_upload_media((storage.foldername(name))[1])
  );

drop policy if exists "media delete" on storage.objects;
create policy "media delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'media'
    and (owner_id = auth.uid()::text or public.is_admin())
  );

-- Silme API'si satırı görebilmeyi de ister; bucket zaten herkese açık.
drop policy if exists "media select" on storage.objects;
create policy "media select" on storage.objects
  for select to authenticated
  using (bucket_id = 'media');
