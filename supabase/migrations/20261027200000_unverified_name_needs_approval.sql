-- Onaysız profilde ad soyad serbestçe değiştirilebilir ama sorumlu onayına
-- gider; onaylı profilde yalnız Türkçe harf düzeltmesi, onaysız. Diğer
-- alanlar (fotoğraf, boy, kilo, mevki) doğrudan yazılır. Talep açıldıysa
-- submit_profile_change talep id'si, açılmadıysa null döner.

create or replace function public.player_profile_values(p_player_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $function$
  select jsonb_build_object(
    'photo_url', p.photo_url,
    'height', p.height,
    'weight', p.weight,
    'main_position', p.main_position,
    'sub_position', p.sub_position,
    'birth_date', p.birth_date,
    'name', p.name,
    'surname', p.surname
  )
  from public.players p
  where p.id = p_player_id
$function$;

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
  v_verified boolean;
  v_req jsonb := '{}'::jsonb;
  v_req_prev jsonb := '{}'::jsonb;
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
  v_verified := exists (select 1 from public.player_verifications v
                         where v.player_id = v_player);
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
        -- Kimliği onaylı profilde ad soyadda yalnız Türkçe harfler
        -- düzeltilebilir ("Bılge" → "Bilge"); onaysız profilde ad soyad
        -- değişebilir ama onaya gider.
        v_txt := btrim(regexp_replace(v_val #>> '{}', '\s+', ' ', 'g'));
        if v_txt = '' then
          raise exception 'Ad soyad boş bırakılamaz.';
        end if;
        if v_verified and public._id_fold(v_txt) is distinct from public._id_fold(
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

  -- Onaysız profilde ad soyad onaya gider; kalan her şey doğrudan yazılır
  -- (fotoğraf, boy, kilo, mevki; onaylı profilde Türkçe harf düzeltmesi).
  if not v_verified and (v_clean ? 'name' or v_clean ? 'surname') then
    select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) into v_req
      from jsonb_each(v_clean) e(k, v) where k in ('name', 'surname');
    select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) into v_req_prev
      from jsonb_each(v_prev) e(k, v) where k in ('name', 'surname');
    v_clean := v_clean - 'name' - 'surname';
    if exists (select 1 from public.profile_change_requests r
                where r.player_id = v_player and r.status = 'pending'
                  and (r.changes ? 'name' or r.changes ? 'surname')) then
      raise exception 'Ad soyad için onay bekleyen talebin var.';
    end if;
  end if;

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

  if v_req <> '{}'::jsonb then
    insert into public.profile_change_requests (player_id, requested_by, changes, previous)
    values (v_player, v_uid, v_req, v_req_prev)
    returning id into v_id;
  end if;
  return v_id;
end;
$function$;;

-- Onaylanan ad soyad talebi de profile yazılır.
create or replace function public.review_profile_change(p_id uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r public.profile_change_requests%rowtype;
  c jsonb;
begin
  select * into r from public.profile_change_requests where id = p_id for update;
  if not found then
    raise exception 'Talep bulunamadı.';
  end if;
  if not public.owns_player(r.player_id) then
    raise exception 'Bu talebi inceleme yetkiniz yok.';
  end if;
  if r.status <> 'pending' then
    raise exception 'Talep zaten sonuçlanmış.';
  end if;

  c := r.changes;
  if p_approve then
    update public.profile_change_requests
    set previous = (
      select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)
      from jsonb_each(public.player_profile_values(r.player_id)) as e(k, v)
      where c ? k
    )
    where id = r.id;

    update public.players
    set photo_url = case when c ? 'photo_url' then c ->> 'photo_url' else photo_url end,
        height = case when c ? 'height' then (c ->> 'height')::int else height end,
        weight = case when c ? 'weight' then (c ->> 'weight')::int else weight end,
        main_position = case when c ? 'main_position' then c ->> 'main_position' else main_position end,
        sub_position = case when c ? 'sub_position' then c ->> 'sub_position' else sub_position end,
        birth_date = case when c ? 'birth_date' then (c ->> 'birth_date')::date else birth_date end,
        name = case when c ? 'name' then c ->> 'name' else name end,
        surname = case when c ? 'surname' then c ->> 'surname' else surname end
    where id = r.player_id;
  end if;

  update public.profile_change_requests
  set status = case when p_approve then 'approved' else 'rejected' end,
      review_note = nullif(trim(coalesce(p_note, '')), ''),
      reviewed_by = auth.uid(),
      reviewed_at = now()
  where id = r.id;
end;
$function$;

create or replace function public.profile_change_lines(p_changes jsonb, p_previous jsonb)
returns text
language sql
immutable
set search_path to ''
as $function$
  select string_agg(
    case k
      when 'height' then 'Boy: ' || coalesce(p_previous ->> k, '-') || ' → ' || (p_changes ->> k) || ' cm'
      when 'weight' then 'Kilo: ' || coalesce(p_previous ->> k, '-') || ' → ' || (p_changes ->> k) || ' kg'
      when 'main_position' then 'Mevki: ' || coalesce(p_previous ->> k, '-') || ' → ' || (p_changes ->> k)
      when 'sub_position' then 'Alt mevki: ' || coalesce(p_previous ->> k, '-') || ' → ' || (p_changes ->> k)
      when 'birth_date' then 'Doğum tarihi: '
        || coalesce(to_char((p_previous ->> k)::date, 'DD.MM.YYYY'), '-') || ' → '
        || to_char((p_changes ->> k)::date, 'DD.MM.YYYY')
      when 'photo_url' then 'Fotoğraf: yeni fotoğraf'
      when 'name' then 'Ad: ' || coalesce(p_previous ->> k, '-') || ' → ' || (p_changes ->> k)
      when 'surname' then 'Soyad: ' || coalesce(p_previous ->> k, '-') || ' → ' || (p_changes ->> k)
      else k end,
    E'\n' order by k)
  from jsonb_object_keys(p_changes) k
$function$;
