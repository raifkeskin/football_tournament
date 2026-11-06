-- Futbolcunun adı/soyadı değişince bağlı hesabın adı (app_users.name) da
-- güncellenir; karşılama ve profil eski adı göstermesin.
create or replace function public.players_sync_account_name()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.auth_uid is not null
     and (new.name is distinct from old.name or new.surname is distinct from old.surname) then
    update public.app_users
       set name = btrim(coalesce(new.name, '') || ' ' || coalesce(new.surname, ''))
     where auth_uid = new.auth_uid::text;
  end if;
  return new;
end;
$$;
drop trigger if exists players_sync_account_name on public.players;
create trigger players_sync_account_name
  after update of name, surname on public.players
  for each row execute function public.players_sync_account_name();

-- Mevcut uyumsuzluk: Aras sorumlusu (Ahmet Şimşek → Yasin Demir).
update public.app_users
   set name = 'Yasin Demir'
 where auth_uid = 'ef3b3f07-a7ae-4494-9421-d05b31bb4dfc';

-- Türkçe harf düzeltmesi yapılmış futbolcuların hesap adları da eşitlenir.
update public.app_users au
   set name = btrim(p.name || ' ' || coalesce(p.surname, ''))
  from public.players p
 where p.auth_uid::text = au.auth_uid
   and lower(btrim(au.name)) <> lower(btrim(p.name || ' ' || coalesce(p.surname, '')));
