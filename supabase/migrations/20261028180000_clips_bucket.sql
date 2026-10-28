-- Yayıncı kesitleri (MP4) için ayrı depo: herkese açık okuma, yalnız admin
-- (ve sunucu) yazar. R2'ye geçilene kadar videolar burada; kesitin adresi
-- match_highlights.video_id'de durur (uygulama http adresini MP4 oynatır).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('clips', 'clips', true, 104857600, array['video/mp4'])
on conflict (id) do update
  set public = true,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists clips_admin_write on storage.objects;
create policy clips_admin_write on storage.objects for insert to authenticated
  with check (bucket_id = 'clips' and public.is_admin());
drop policy if exists clips_admin_update on storage.objects;
create policy clips_admin_update on storage.objects for update to authenticated
  using (bucket_id = 'clips' and public.is_admin());
drop policy if exists clips_admin_delete on storage.objects;
create policy clips_admin_delete on storage.objects for delete to authenticated
  using (bucket_id = 'clips' and public.is_admin());

-- Yayıncının teslim ettiği kesit: source = 'provider'.
alter table public.match_highlights drop constraint if exists match_highlights_source_check;
alter table public.match_highlights add constraint match_highlights_source_check
  check (source = any (array['ai', 'manual', 'provider']));
