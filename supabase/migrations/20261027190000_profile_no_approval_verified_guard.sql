-- 1) Bilgilerim: hiçbir alan onaya gitmez. Fotoğraf, boy, kilo ve mevki
--    doğrudan yazılır (kişisel veri; kişi isterse girer). Ad soyadda yalnız
--    Türkçe harfler düzeltilebilir. Doğum tarihi uygulamadan değişmez.
--    submit_profile_change her zaman null döner (talep açılmaz).
-- 2) Kimliği onaylı profilde admin dışında kimse doğum tarihini
--    değiştiremez; ad soyadda yalnız Türkçe harf düzeltmesi yapılabilir
--    (kadro formu, yönetim ekranları, eski sürümler dahil).

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
  v_main text;
  v_sub text;
  v_name text;
  v_surname text;
  v_txt text;
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

  v_current := public.player_profile_values(v_player)
    || (select jsonb_build_object('name', p.name, 'surname', p.surname)
          from public.players p where p.id = v_player);
  v_photo_prefix := '/storage/v1/object/public/media/profile_requests/'
    || v_uid::text || '/';

  for v_key, v_val in select * from jsonb_each(p_changes) loop
    if v_key = 'birth_date' then
      raise exception 'Doğum tarihi uygulamadan değiştirilemez.';
    end if;
    if v_key not in ('photo_url', 'height', 'weight', 'main_position',
                     'sub_position', 'birth_date', 'name', 'surname') then
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
      when 'name', 'surname' then
        -- Ad soyadda yalnız Türkçe harfler düzeltilebilir ("Bılge" →
        -- "Bilge", "Kagan" → "Kağan"); başka ad yazılamaz.
        v_txt := btrim(regexp_replace(v_val #>> '{}', '\s+', ' ', 'g'));
        if v_txt = '' then
          raise exception 'Ad soyad boş bırakılamaz.';
        end if;
        if public._id_fold(v_txt) is distinct from public._id_fold(
             (select case when v_key = 'name' then p.name else p.surname end
                from public.players p where p.id = v_player)) then
          raise exception 'Ad soyadda yalnız Türkçe harfler (ı, ğ, ş, ü, ö, ç) düzeltilebilir.';
        end if;
        v_val := to_jsonb(v_txt);
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

  -- Hiçbir alan onaya gitmez: kişisel veriyi kişi kendisi girer
  -- (fotoğraf, boy, kilo, mevki, ad soyadda Türkçe harf düzeltmesi).
  v_main := coalesce(v_clean ->> 'main_position', v_current ->> 'main_position');
  v_sub := coalesce(v_clean ->> 'sub_position', v_current ->> 'sub_position');
  if v_main = 'Kaleci' or v_sub = '' then
    v_sub := null;
  end if;
  update public.players p
     set photo_url = coalesce(v_clean ->> 'photo_url', p.photo_url),
         height = coalesce((v_clean ->> 'height')::int, p.height),
         weight = coalesce((v_clean ->> 'weight')::int, p.weight),
         main_position = v_main,
         sub_position = v_sub,
         other_positions = case
           when (v_clean ? 'main_position' or v_clean ? 'sub_position')
                and v_sub is not null
             then array_remove(p.other_positions, v_sub)
           else p.other_positions end,
         name = coalesce(v_clean ->> 'name', p.name),
         surname = coalesce(v_clean ->> 'surname', p.surname)
   where p.id = v_player;
  return null;
end;
$function$;

create or replace function public.players_guard_verified_identity()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if not exists (select 1 from public.player_verifications v
                  where v.player_id = old.id) then
    return new;
  end if;
  if new.birth_date is distinct from old.birth_date then
    raise exception 'Kimliği onaylı profilin doğum tarihi değiştirilemez.';
  end if;
  if public._id_fold(new.name) is distinct from public._id_fold(old.name)
     or public._id_fold(new.surname) is distinct from public._id_fold(old.surname) then
    raise exception 'Kimliği onaylı profilin adında yalnız Türkçe harfler düzeltilebilir.';
  end if;
  return new;
end;
$$;

drop trigger if exists players_guard_verified_identity on public.players;
create trigger players_guard_verified_identity
  before update of birth_date, name, surname on public.players
  for each row execute function public.players_guard_verified_identity();
