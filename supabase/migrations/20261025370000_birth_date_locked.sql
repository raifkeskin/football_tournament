-- Futbolcu kendi doğum tarihini uygulamadan değiştiremez (yalnız veritabanından).
-- Eski APK'lar da talep gönderemez.
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
        if (v_val #>> '{}') not in ('Kaleci', 'Stoper', 'Bek', 'Defansif',
            'Merkez', 'Ofansif', 'Kanat', 'Santrfor', 'Kanat Forvet') then
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
