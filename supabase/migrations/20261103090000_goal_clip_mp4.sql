-- Gol kesitlerinin MP4 hâli: Mac'teki betik (tools/goal_clips) YouTube
-- yayınından yalnız gol aralığını indirir, iki MP4 üretir ve clips deposuna
-- yükler:
--   clip_url  yatay (16:9) kesit, uygulamada YouTube yerine oynar
--   story_url Instagram hikâyesi (9:16): skor bandı, golcü, Lig Masası imzası
-- clip_tries / clip_error: başarısız denemeler (3 denemeden sonra bırakılır).
-- Yeni özellik: yalnız admin; goal_clip_mp4_enabled açılınca herkes.

alter table public.match_highlights
  add column if not exists clip_url text,
  add column if not exists story_url text,
  add column if not exists clip_tries smallint not null default 0,
  add column if not exists clip_error text;

insert into public.app_settings (key, value)
values ('goal_clip_mp4_enabled', 'false'::jsonb)
on conflict (key) do nothing;

-- Betik aynı adla yeniden yüklerken (x-upsert) depo satırını okuyabilmeli.
drop policy if exists clips_admin_read on storage.objects;
create policy clips_admin_read on storage.objects
  for select to authenticated
  using (bucket_id = 'clips' and public.is_admin());
