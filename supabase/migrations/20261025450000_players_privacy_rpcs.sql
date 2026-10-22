-- players gizliliği (1. aşama, yalnız ekleme): uygulama oyuncu telefonunu
-- tablodan okumayı bırakır; telefon yalnız yetkiliye bu fonksiyonlarla
-- gelir. Okuma yetkisinin kaldırılması ayrı betikte
-- (supabase/manual/players_revoke_phone.sql), yeni sürüm yaygınlaşınca.

-- Yetkiliye oyuncu telefonları: admin, oyuncunun turnuva/bölge sahibi,
-- takım sorumlusu ya da kişinin kendisi. Yetkisiz satır dönmez.
create or replace function public.player_phones(p_ids uuid[])
returns table (id uuid, phone text)
language sql
stable
security definer
set search_path to ''
as $function$
  select p.id, public.phone_raw10(p.phone)
  from public.players p
  where p.id = any(p_ids)
    and public.phone_raw10(p.phone) is not null
    and auth.uid() is not null
    and (p.auth_uid = auth.uid()
         or public.owns_player(p.id)
         or public.manages_player(p.id))
$function$;
revoke all on function public.player_phones(uuid[]) from public, anon;
grant execute on function public.player_phones(uuid[]) to authenticated;

-- Giriş yapan kişinin oyuncu profili: eşleşmiş kayıt, yoksa hesabın
-- numarasıyla.
create or replace function public.my_player_id()
returns uuid
language sql
stable
security definer
set search_path to ''
as $function$
  select p.id
  from public.players p
  where auth.uid() is not null
    and (p.auth_uid = auth.uid()
         or public.phone_raw10(p.phone) = (
              select coalesce(public.phone_raw10(u.phone),
                              split_part(u.email, '@', 1))
              from auth.users u where u.id = auth.uid()))
  order by (p.auth_uid = auth.uid()) desc nulls last
  limit 1
$function$;
revoke all on function public.my_player_id() from public, anon;
grant execute on function public.my_player_id() to authenticated;

-- Yetkili (admin, kurucu başkan, bölge sorumlusu) yeni oyuncu açar ve
-- id'sini alır. Telefon verilmişse ve o
-- numarada oyuncu varsa mevcut oyuncu döner (eski davranış). Ad + soyad +
-- doğum tarihi aynı başka kayıt varsa players_identity_uq hatası verir.
create or replace function public.staff_create_player(
  p_name text,
  p_surname text,
  p_birth date,
  p_phone text default null,
  p_main text default null,
  p_foot text default null,
  p_height int default null,
  p_weight int default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_raw text := public.phone_raw10(p_phone);
  v_id uuid;
begin
  -- Oyuncu ekleme kuralı players_insert ile aynı (takım sorumlusu kadro
  -- talebiyle ekler).
  if v_uid is null or not (
       public.is_admin()
    or public.is_any_league_owner()
    or public.is_any_region_owner()) then
    raise exception 'Oyuncu ekleme yetkiniz yok.';
  end if;
  if nullif(trim(coalesce(p_name, '')), '') is null then
    raise exception 'Ad gerekli.';
  end if;
  if v_raw is not null and v_raw !~ '^5[0-9]{9}$' then
    raise exception 'Telefon no geçersiz.';
  end if;
  if v_raw is not null then
    select id into v_id from public.players
     where public.phone_raw10(phone) = v_raw limit 1;
    if found then
      return v_id;
    end if;
  end if;

  insert into public.players (
    name, surname, birth_date, phone, main_position, preferred_foot,
    height, weight
  ) values (
    trim(p_name), nullif(trim(coalesce(p_surname, '')), ''), p_birth, v_raw,
    nullif(trim(coalesce(p_main, '')), ''), nullif(trim(coalesce(p_foot, '')), ''),
    p_height, p_weight
  ) returning id into v_id;
  return v_id;
end;
$function$;
revoke all on function public.staff_create_player(text, text, date, text, text, text, int, int) from public, anon;
grant execute on function public.staff_create_player(text, text, date, text, text, text, int, int) to authenticated;
