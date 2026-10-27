-- Alt mevki seçenekleri Mevki sekmesiyle aynı: bek, kanat ve kanat forvet
-- sol / sağ ayrı; kalecinin alt mevkisi yok. Tarafı bilinmeyen eski değerler
-- (Bek, Kanat, Kanat Forvet) kayıtta kalır, form yeniden seçtirir.

update public.players
   set sub_position = null
 where main_position = 'Kaleci' and sub_position = 'Kaleci';

CREATE OR REPLACE FUNCTION public.submit_profile_change(p_changes jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_player uuid;
  v_current jsonb;
  v_clean jsonb := '{}'::jsonb;
  v_prev jsonb := '{}'::jsonb;
  v_key text;
  v_val jsonb;
  v_locked text[];
  v_photo_prefix text;
  v_id uuid;
  v_int int;
  v_date date;
begin
  if v_uid is null then
    raise exception 'Giriş yapmalısınız.';
  end if;
  if p_changes is null or jsonb_typeof(p_changes) <> 'object' then
    raise exception 'Geçersiz talep.';
  end if;

  select id into v_player from public.players where auth_uid = v_uid limit 1;
  if v_player is null then
    raise exception 'Hesabınıza bağlı oyuncu kaydı yok.';
  end if;

  v_current := public.player_profile_values(v_player);
  v_photo_prefix := '/storage/v1/object/public/media/profile_requests/'
    || v_uid::text || '/';

  for v_key, v_val in select * from jsonb_each(p_changes) loop
    if v_key = 'birth_date' then
      raise exception 'Doğum tarihi uygulamadan değiştirilemez.';
    end if;
    if v_key not in ('photo_url', 'height', 'weight', 'main_position',
                     'sub_position', 'birth_date') then
      raise exception 'Bu alan değiştirilemez: %', v_key;
    end if;

    if jsonb_typeof(v_val) = 'null' then
      raise exception 'Alan boş bırakılamaz: %', v_key;
    end if;

    case v_key
      when 'photo_url' then
        if position(v_photo_prefix in (v_val #>> '{}')) = 0 then
          raise exception 'Fotoğraf geçersiz.';
        end if;
      when 'height' then
        v_int := (v_val #>> '{}')::int;
        if v_int < 120 or v_int > 230 then
          raise exception 'Boy 120-230 cm arasında olmalı.';
        end if;
        v_val := to_jsonb(v_int);
      when 'weight' then
        v_int := (v_val #>> '{}')::int;
        if v_int < 35 or v_int > 200 then
          raise exception 'Kilo 35-200 kg arasında olmalı.';
        end if;
        v_val := to_jsonb(v_int);
      when 'main_position' then
        if (v_val #>> '{}') not in ('Kaleci', 'Defans', 'Orta Saha', 'Forvet') then
          raise exception 'Mevki geçersiz.';
        end if;
      when 'sub_position' then
        -- Boş = alt mevki yok (kaleci).
        if (v_val #>> '{}') not in ('', 'Stoper', 'Sol Bek', 'Sağ Bek',
            'Defansif', 'Merkez', 'Ofansif', 'Sol Kanat', 'Sağ Kanat',
            'Santrfor', 'Sol Kanat Forvet', 'Sağ Kanat Forvet') then
          raise exception 'Alt mevki geçersiz.';
        end if;
      when 'birth_date' then
        v_date := (v_val #>> '{}')::date;
        if v_date < date '1940-01-01'
           or v_date > (current_date - interval '10 years')::date then
          raise exception 'Doğum tarihi geçersiz.';
        end if;
        v_val := to_jsonb(v_date);
    end case;

    -- Değişmeyen alan talebe girmez.
    if (v_current -> v_key) is distinct from v_val then
      v_clean := v_clean || jsonb_build_object(v_key, v_val);
      v_prev := v_prev || jsonb_build_object(v_key, v_current -> v_key);
    end if;
  end loop;

  if v_clean = '{}'::jsonb then
    raise exception 'Değişiklik yok.';
  end if;

  -- Onay bekleyen alanlar kilitli.
  select array_agg(distinct k) into v_locked
  from public.profile_change_requests r,
       lateral jsonb_object_keys(r.changes) k
  where r.player_id = v_player
    and r.status = 'pending'
    and v_clean ? k;
  if v_locked is not null then
    raise exception 'Onay bekleyen alanlar tekrar gönderilemez: %',
      array_to_string(v_locked, ', ');
  end if;

  insert into public.profile_change_requests (player_id, requested_by, changes, previous)
  values (v_player, v_uid, v_clean, v_prev)
  returning id into v_id;
  return v_id;
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
     where p.birth_date = p_birth
       and public.tr_fold(p.surname) = public.tr_fold(v_last)
       and (public.tr_fold(p.name) = public.tr_fold(v_first)
            or public.tr_fold(v_first) like public.tr_fold(p.name) || ' %'
            or public.tr_fold(p.name) like public.tr_fold(v_first) || ' %')
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
    -- Mevcut profil: kişinin kendi girdikleri yazılır; ad ve doğum
    -- tarihi profildeki gibi kalır.
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

  insert into public.player_verifications (player_id, tc_hash, verified_by)
  values (v_player, v_hash, v_uid)
  on conflict (player_id) do nothing;
  insert into public.identity_events (player_id, action, user_id)
  values (v_player, 'register', v_uid);

  return 'ok';
end;
$function$;
