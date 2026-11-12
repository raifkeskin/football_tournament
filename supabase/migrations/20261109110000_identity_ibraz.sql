-- Kimlik ibrazıyla onay: kimliğini okutmadan kayıt olan futbolcu "onay
-- bekleyen" olur; yetkili kimliği yüz yüze görüp onaylar (turuncu tik).
-- Açık TC yalnız onay bekleme süresince saklanır, onay/ret'te silinir.

insert into public.app_settings (key, value) values
  ('ibraz_enabled', 'false'::jsonb),
  ('ibraz_approve_owner', 'true'::jsonb),
  ('ibraz_approve_region', 'false'::jsonb)
on conflict (key) do nothing;

create or replace function public.ibraz_flag(p_key text)
 returns boolean language sql stable security definer set search_path to ''
as $$ select coalesce((select value = 'true'::jsonb from public.app_settings where key = p_key), false) $$;

create table if not exists public.identity_pending (
  player_id uuid primary key references public.players (id) on delete cascade,
  tc_plain text not null,
  requested_at timestamptz not null default now()
);
alter table public.identity_pending enable row level security;
revoke all on public.identity_pending from anon, authenticated;

-- Bu oyuncuyu ibrazla onaylayabilir mi? Admin her zaman; kurucu başkan ve
-- bölge sorumlusu ayarlara göre, yalnız kendi turnuvası / bölgesindeki
-- (ya da henüz bir kadroya yazılmamış) kayıtları.
create or replace function public._ibraz_can_approve(p_player uuid)
 returns boolean language sql stable security definer set search_path to ''
as $$
  select auth.uid() is not null and (
    public.is_admin()
    or (public.ibraz_flag('ibraz_enabled') and (
      exists (
        select 1 from public.season_team_players stp
          join public.seasons s on s.id = stp.season_id
         where stp.player_id = p_player and coalesce(stp.is_active, true)
           and (
             (public.ibraz_flag('ibraz_approve_owner') and public.owns_league(s.league_id))
             or (public.ibraz_flag('ibraz_approve_region') and exists (
                   select 1 from public.region_owners ro
                     join public.season_regions sr on sr.id = ro.region_id
                    where sr.season_id = s.id and ro.user_id = auth.uid()))
           ))
      or (
        not exists (select 1 from public.season_team_players x
                     where x.player_id = p_player and coalesce(x.is_active, true))
        and (
          (public.ibraz_flag('ibraz_approve_owner')
             and exists (select 1 from public.leagues l where public.owns_league(l.id)))
          or (public.ibraz_flag('ibraz_approve_region')
             and exists (select 1 from public.region_owners ro where ro.user_id = auth.uid()))
        ))
    ))
  )
$$;

create or replace function public.ibraz_pending_list()
 returns jsonb language sql stable security definer set search_path to ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'name', p.name, 'surname', p.surname,
      'birth', p.birth_date, 'tc', ip.tc_plain,
      'requested_at', ip.requested_at,
      'team', (select t.name from public.season_team_players stp
                 join public.teams t on t.id = stp.team_id
                where stp.player_id = p.id and coalesce(stp.is_active, true)
                limit 1)
    ) order by ip.requested_at), '[]'::jsonb)
    from public.identity_pending ip
    join public.players p on p.id = ip.player_id
   where public._ibraz_can_approve(ip.player_id)
$$;

create or replace function public.ibraz_pending_count()
 returns integer language sql stable security definer set search_path to ''
as $$
  select count(*)::int from public.identity_pending ip
   where public._ibraz_can_approve(ip.player_id)
$$;

-- Onay: bilgiler kimlikle aynıysa olduğu gibi, yanlışsa düzeltilerek.
create or replace function public.ibraz_approve(
  p_player uuid, p_first text, p_last text, p_birth date, p_tc text)
 returns text language plpgsql security definer set search_path to ''
as $$
declare
  v_first text := coalesce(public.tr_name_fix(p_first), '');
  v_last text := coalesce(public.tr_name_fix(p_last), '');
  v_hash text;
begin
  if not public._ibraz_can_approve(p_player) then
    return 'forbidden';
  end if;
  if not exists (select 1 from public.identity_pending where player_id = p_player) then
    return 'not_pending';
  end if;
  if length(v_first) < 2 or length(v_last) < 2
     or p_birth is null or p_birth < date '1940-01-01'
     or p_birth > (current_date - interval '5 years')::date then
    return 'invalid_data';
  end if;
  if not public.tc_valid(p_tc) then
    return 'invalid_tc';
  end if;
  v_hash := public._identity_hash(p_tc);
  if exists (select 1 from public.player_verifications v
             where v.tc_hash = v_hash and v.player_id <> p_player) then
    return 'tc_taken';
  end if;
  begin
    update public.players
       set name = v_first, surname = v_last, birth_date = p_birth
     where id = p_player;
  exception when unique_violation then
    return 'duplicate';
  end;
  insert into public.player_verifications (player_id, tc_hash, method, verified_by)
  values (p_player, v_hash, 'ibraz', auth.uid())
  on conflict (player_id) do update
    set tc_hash = excluded.tc_hash, method = 'ibraz',
        verified_at = now(), verified_by = excluded.verified_by;
  delete from public.identity_pending where player_id = p_player;
  insert into public.identity_events (player_id, action, user_id)
  values (p_player, 'ibraz_approve', auth.uid());
  return 'ok';
end;
$$;

create or replace function public.ibraz_reject(p_player uuid)
 returns text language plpgsql security definer set search_path to ''
as $$
begin
  if not public._ibraz_can_approve(p_player) then
    return 'forbidden';
  end if;
  delete from public.identity_pending where player_id = p_player;
  insert into public.identity_events (player_id, action, user_id)
  values (p_player, 'ibraz_reject', auth.uid());
  return 'ok';
end;
$$;

-- Tike dokununca: yöntem, tarih, onaylayan.
create or replace function public.identity_badge_info(p_player uuid)
 returns jsonb language sql stable security definer set search_path to ''
as $$
  select jsonb_build_object(
    'method', v.method, 'verified_at', v.verified_at,
    'by', coalesce(
      (select nullif(trim(concat_ws(' ', pl.name, pl.surname)), '')
         from public.players pl where pl.auth_uid = v.verified_by limit 1),
      (select au.name from public.app_users au where au.auth_uid = v.verified_by::text limit 1),
      (select coalesce(a.display_name, a.name) from public.admins a where a.user_id = v.verified_by limit 1)))
    from public.player_verifications v where v.player_id = p_player
$$;

grant execute on function public.ibraz_pending_list() to authenticated;
grant execute on function public.ibraz_pending_count() to authenticated;
grant execute on function public.ibraz_approve(uuid, text, text, date, text) to authenticated;
grant execute on function public.ibraz_reject(uuid) to authenticated;
grant execute on function public.identity_badge_info(uuid) to anon, authenticated;
revoke execute on function public._ibraz_can_approve(uuid) from anon, public;
grant execute on function public._ibraz_can_approve(uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.register_player_manual(p_phone text, p_code text, p_password text, p_first text, p_last text, p_birth date, p_tc text, p_main text, p_sub text, p_foot text, p_height integer, p_weight integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_raw text := public.phone_raw10(p_phone);
  v_first text := coalesce(public.tr_name_fix(p_first), '');
  v_last text := coalesce(public.tr_name_fix(p_last), '');
  v_hash text;
  v_player uuid;
  v_auth uuid;
  v_count int;
  v_uid uuid;
  v_res text;
  v_phone_owner uuid;
  v_new_first text;
  v_new_last text;
  v_new_birth date;
begin
  if not public.self_registration_enabled() or not public.ibraz_flag('ibraz_enabled') then
    return 'disabled';
  end if;
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    return 'invalid_phone';
  end if;
  if not public.tc_valid(p_tc) then
    return 'invalid_tc';
  end if;
  if length(v_first) < 2 or length(v_last) < 2
     or p_birth is null or p_birth < date '1940-01-01'
     or p_birth > (current_date - interval '10 years')::date
     or coalesce(p_main, '') not in ('Kaleci', 'Defans', 'Orta Saha', 'Forvet')
     or (p_sub is not null and p_sub not in ('Stoper', 'Sol Bek', 'Sağ Bek',
         'Defansif', 'Merkez', 'Ofansif', 'Sol Kanat', 'Sağ Kanat', 'Santrfor',
         'Sol Kanat Forvet', 'Sağ Kanat Forvet'))
     or (p_foot is not null and p_foot not in ('Sağ', 'Sol', 'Her İkisi'))
     or (p_height is not null and p_height not between 120 and 230)
     or (p_weight is not null and p_weight not between 35 and 200) then
    return 'invalid_data';
  end if;
  if p_password is null or length(p_password) not between 6 and 10
     or p_password !~ '[^A-Za-z]' then
    return 'weak_password';
  end if;
  if exists (select 1 from auth.users where email = v_raw || '@masterclass.com') then
    return 'has_account';
  end if;

  v_hash := public._identity_hash(p_tc);
  -- Bu TC zaten onaylı bir profilde: okutarak (çip) kayıt olmalı.
  if exists (select 1 from public.player_verifications v where v.tc_hash = v_hash) then
    return 'tc_taken';
  end if;

  if exists (select 1 from public.identity_pending ip where ip.tc_plain = p_tc) then
    return 'tc_pending';
  end if;
  -- Aynı kişi: önce TC onayı, sonra numarası (kodla doğrulanır) kayıtlı
  -- profil, yoksa ad + soyad + doğum tarihi tutan onaysız profil.
  if v_player is null then
    select p.id into v_phone_owner from public.players p where p.phone = v_raw;
    if v_phone_owner is not null then
      -- Başka bir kimlikle onaylı ya da hesabı olan profil: numara başkasının.
      if exists (select 1 from public.player_verifications v
                  where v.player_id = v_phone_owner)
         or exists (select 1 from public.players p
                     where p.id = v_phone_owner and p.auth_uid is not null) then
        return 'phone_taken';
      end if;
      v_player := v_phone_owner;
    end if;
  end if;
  if v_player is null then
    select count(*), min(p.id::text)::uuid into v_count, v_player
      from public.players p
     where (p.birth_date = p_birth
            -- Yalnız yılı bilinen profil (01.01): aynı yıl yeter.
            or (to_char(p.birth_date, 'MM-DD') = '01-01'
                and extract(year from p.birth_date) = extract(year from p_birth)))
       and (' ' || public._id_fold(v_last) || ' ' like '% ' || public._id_fold(p.surname) || ' %'
            or ' ' || public._id_fold(p.surname) || ' ' like '% ' || public._id_fold(v_last) || ' %')
       and (' ' || public._id_fold(v_first) || ' ' like '% ' || public._id_fold(p.name) || ' %'
            or ' ' || public._id_fold(p.name) || ' ' like '% ' || public._id_fold(v_first) || ' %')
       and not exists (select 1 from public.player_verifications v
                        where v.player_id = p.id);
    if v_count > 1 then
      return 'ambiguous';
    end if;
    if v_player is not null then
      select auth_uid into v_auth from public.players where id = v_player;
    end if;
  end if;
  if v_auth is not null then
    return 'profile_has_account';
  end if;

  -- Kimlikle bulunan profil başka, numara başka bir profilde: numara
  -- başkasının.
  select p.id into v_phone_owner from public.players p where p.phone = v_raw;
  if v_phone_owner is not null and v_phone_owner is distinct from v_player then
    return 'phone_taken';
  end if;

  v_res := public._otp_consume(v_raw, p_code);
  if v_res <> 'ok' then
    return v_res;
  end if;

  if v_player is null then
    insert into public.players (
      name, surname, birth_date, phone, main_position, sub_position,
      preferred_foot, height, weight
    ) values (
      v_first, v_last, p_birth, v_raw, p_main, p_sub, p_foot, p_height, p_weight
    ) returning id into v_player;
  else
    -- Mevcut (onaysız) profil: ad, soyad, doğum tarihi olduğu gibi kalır;
    -- onay sırasında yetkili kimlikle karşılaştırıp düzeltir.
    update public.players
       set phone = v_raw,
           main_position = p_main,
           sub_position = case when p_main = 'Kaleci' then null
                               else coalesce(p_sub, sub_position) end,
           preferred_foot = coalesce(p_foot, preferred_foot),
           height = coalesce(p_height, height),
           weight = coalesce(p_weight, weight)
     where id = v_player;
  end if;

  v_uid := public.set_phone_account_password(
    v_raw, p_password, false, v_first || ' ' || v_last);

  -- Hesap açılırken aynı numaralı başka bir kayıt bağlandıysa düzeltilir.
  update public.players set auth_uid = null
   where auth_uid = v_uid and id <> v_player;
  update public.players set auth_uid = v_uid where id = v_player;

  -- Onaysız: TC yalnız onay bekleme süresince açık tutulur (onay/ret'te silinir).
  insert into public.identity_pending (player_id, tc_plain)
  values (v_player, p_tc)
  on conflict (player_id) do update set tc_plain = excluded.tc_plain, requested_at = now();
  insert into public.identity_events (player_id, action, user_id)
  values (v_player, 'register_ibraz', v_uid);

  return 'ok';
end;
$function$;

grant execute on function public.register_player_manual(text, text, text, text, text, date, text, text, text, text, integer, integer) to anon, authenticated;
