-- Profil talebi fotoğraflarının temizliği: karar veren sorumlu / admin,
--   - reddedilen talebin yeni fotoğrafını,
--   - onaylanan talepte yerine yenisi geçen eski talep fotoğrafını
-- depodan silebilir. (Geri çekilen talebin fotoğrafını futbolcu zaten
-- kendi siler.)
drop policy if exists "media delete profile request photos" on storage.objects;
create policy "media delete profile request photos" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'media'
    and (storage.foldername(name))[1] = 'profile_requests'
    and exists (
      select 1 from public.profile_change_requests r
      where public.owns_player(r.player_id)
        and (
          (r.status = 'rejected'
            and r.changes ->> 'photo_url' like '%/media/' || name)
          or (r.status = 'approved'
            and r.previous ->> 'photo_url' like '%/media/' || name)
        )
    )
  );
