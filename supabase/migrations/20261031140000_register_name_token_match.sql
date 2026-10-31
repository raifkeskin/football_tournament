-- Kendi kaydı: ad ve soyad eşleşmesi kelime bazında. Kimlikteki isimlerden
-- biri profildeki adla tutarsa yeter ("Ali Hakan" ↔ "Hakan"; önceden yalnız
-- profildeki ad başta olunca tutuyordu). Soyadında da aynı kural. Türkçe
-- harfler de eşitlenir (_id_fold: AKTAS = Aktaş).

CREATE OR REPLACE FUNCTION public.register_player_precheck(p_first text, p_last text, p_birth date, p_tc text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_hash text;
  v_player uuid;
  v_auth uuid;
  v_count int;
begin
  if not public.self_registration_enabled() then
    return 'disabled';
  end if;
  if not public.tc_valid(p_tc) then
    return 'invalid_tc';
  end if;
  v_hash := public._identity_hash(p_tc);

  select v.player_id, p.auth_uid into v_player, v_auth
    from public.player_verifications v
    join public.players p on p.id = v.player_id
   where v.tc_hash = v_hash;
  if v_player is null then
    select count(*), min(p.id::text)::uuid into v_count, v_player
      from public.players p
     where (p.birth_date = p_birth
            -- Yalnız yılı bilinen profil (01.01): aynı yıl yeter.
            or (to_char(p.birth_date, 'MM-DD') = '01-01'
                and extract(year from p.birth_date) = extract(year from p_birth)))
       and (' ' || public._id_fold(btrim(p_last)) || ' ' like '% ' || public._id_fold(p.surname) || ' %'
            or ' ' || public._id_fold(p.surname) || ' ' like '% ' || public._id_fold(btrim(p_last)) || ' %')
       and (' ' || public._id_fold(btrim(p_first)) || ' ' like '% ' || public._id_fold(p.name) || ' %'
            or ' ' || public._id_fold(p.name) || ' ' like '% ' || public._id_fold(btrim(p_first)) || ' %')
       and not exists (select 1 from public.player_verifications v
                        where v.player_id = p.id);
    if v_count > 1 then
      return 'ambiguous';
    end if;
    if v_player is not null then
      select auth_uid into v_auth from public.players where id = v_player;
    end if;
  end if;
  insert into public.identity_events (player_id, action, user_id)
  values (v_player, 'register_check', null);
  return case when v_auth is not null then 'profile_has_account' else 'ok' end;
end;
$function$;

CREATE OR REPLACE FUNCTION public.register_player(p_phone text, p_code text, p_password text, p_first text, p_last text, p_birth date, p_tc text, p_main text, p_sub text, p_foot text, p_height integer, p_weight integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_raw text := public.phone_raw10(p_phone);
  v_first text := btrim(coalesce(p_first, ''));
  v_last text := btrim(coalesce(p_last, ''));
  v_hash text;
  v_player uuid;
  v_auth uuid;
  v_count int;
  v_uid uuid;
  v_res text;
  v_phone_owner uuid;
begin
  if not public.self_registration_enabled() then
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

  -- Aynı kişi: önce TC onayı, yoksa ad + soyad + doğum tarihi tutan
  -- onaysız profil.
  select v.player_id, p.auth_uid into v_player, v_auth
    from public.player_verifications v
    join public.players p on p.id = v.player_id
   where v.tc_hash = v_hash;
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

  -- Numara başka bir profilde kayıtlıysa: ad soyad tutan onaysız profil
  -- o kişidir (bağlanır); tutmuyorsa numara başkasınındır.
  select p.id into v_phone_owner from public.players p where p.phone = v_raw;
  if v_phone_owner is not null and v_phone_owner is distinct from v_player then
    if v_player is null and exists (
      select 1 from public.players p
       where p.id = v_phone_owner
         and p.auth_uid is null
         and (' ' || public._id_fold(v_last) || ' ' like '% ' || public._id_fold(p.surname) || ' %'
            or ' ' || public._id_fold(p.surname) || ' ' like '% ' || public._id_fold(v_last) || ' %')
         and (' ' || public._id_fold(v_first) || ' ' like '% ' || public._id_fold(p.name) || ' %'
            or ' ' || public._id_fold(p.name) || ' ' like '% ' || public._id_fold(v_first) || ' %')
         and not exists (select 1 from public.player_verifications v
                          where v.player_id = p.id)
    ) then
      v_player := v_phone_owner;
    else
      return 'phone_taken';
    end if;
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
    -- Mevcut profil: kişinin kendi girdikleri yazılır; ad profildeki gibi
    -- kalır, doğum tarihi kimlikteki tarihle düzelir.
    update public.players
       set phone = v_raw,
           -- Doğum tarihi kimlik çipindekiyle düzelir (aynı ad soyad ve
           -- tarihte başka profil yoksa; players_identity_uq).
           birth_date = case when exists (
                               select 1 from public.players o
                                where o.id <> v_player
                                  and public.norm_person_name(o.name::text)
                                      = public.norm_person_name(name::text)
                                  and public.norm_person_name(o.surname)
                                      = public.norm_person_name(surname)
                                  and o.birth_date = p_birth)
                             then birth_date else p_birth end,
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

  insert into public.player_verifications (player_id, tc_hash, verified_by)
  values (v_player, v_hash, v_uid)
  on conflict (player_id) do nothing;
  insert into public.identity_events (player_id, action, user_id)
  values (v_player, 'register', v_uid);

  return 'ok';
end;
$function$;
