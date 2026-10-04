-- Yönetici (kurucu başkan, bölge sorumlusu, takım sorumlusu) profil fotoğrafı.
-- Fotoğraf media/staff/<auth uid>/ klasörüne yüklenir; adres app_users.photo_url.

drop policy if exists "media insert own staff photo" on storage.objects;
create policy "media insert own staff photo" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'media'
    and (storage.foldername(name))[1] = 'staff'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

-- Kendi fotoğrafını kaydeder (app_users satırı yoksa telefonla açılır).
create or replace function public.set_my_photo(p_url text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_raw text := split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1);
  v_url text := nullif(trim(coalesce(p_url, '')), '');
begin
  if v_uid is null then
    raise exception 'Giriş yapmalısınız.' using errcode = '42501';
  end if;
  if v_url is not null and v_url not like '%/storage/v1/object/public/media/staff/' || v_uid::text || '/%' then
    raise exception 'Geçersiz fotoğraf adresi.';
  end if;
  update public.app_users set photo_url = v_url where auth_uid = v_uid::text;
  if not found and v_raw ~ '^5[0-9]{9}$' then
    insert into public.app_users (phone, auth_uid, role, photo_url)
    values (v_raw, v_uid::text, 'player', v_url)
    on conflict (phone) do update
      set auth_uid = excluded.auth_uid, photo_url = excluded.photo_url;
  end if;
end;
$$;
revoke all on function public.set_my_photo(text) from public, anon;
grant execute on function public.set_my_photo(text) to authenticated;
