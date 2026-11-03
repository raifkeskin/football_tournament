-- Admin'in eklediği futbolcu fotoğrafı izin beklemeden görünür (fotoğraf
-- izni admin tarafından alınmış sayılır). Futbolcu izni açıkça geri
-- aldıysa (son kayıt granted = false) admin de aşamaz; yine gizlenir.
create or replace function public.players_photo_consent_guard()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if coalesce(trim(new.photo_url), '') <> '' then
    if not public.player_photo_ok(new.id)
       and not (
         public.is_admin()
         and not exists (
           select 1 from (
             select c.granted from public.player_consents c
              where c.player_id = new.id and c.consent_type = 'photo_publish'
              order by c.created_at desc limit 1) last
            where last.granted = false)
       ) then
      insert into public.player_photo_hold (player_id, photo_url)
      values (new.id, new.photo_url)
      on conflict (player_id) do update
        set photo_url = excluded.photo_url, held_at = now();
      new.photo_url := null;
    elsif tg_op = 'UPDATE' then
      -- Görünür olan yeni fotoğraf bekleyeni geçersiz kılar.
      delete from public.player_photo_hold where player_id = new.id;
    end if;
  elsif tg_op = 'UPDATE'
    and coalesce(current_setting('app.photo_hold', true), '') <> '1' then
    delete from public.player_photo_hold where player_id = new.id;
  end if;
  return new;
end;
$$;
