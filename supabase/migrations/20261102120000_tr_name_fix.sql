-- Kimlik çipinden (MRZ) gelen adlarda Türkçe harf yok: "BILAL CICEK".
-- Her kelime, sistemdeki oyuncu adlarında harfleri sadeleştirilince aynı olan
-- en yaygın yazımla değiştirilir (Bilal, Çiçek). Bulunamazsa uygulamanın
-- I→ı çevirisi ünlü uyumuyla düzeltilir (Cıcek → Cicek). Kişinin kendisi
-- Türkçe harfle yazdığı kelimeye (ç, ğ, ö, ş, ü içeren) dokunulmaz.
CREATE OR REPLACE FUNCTION public.tr_name_word_fix(p_word text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w text := btrim(coalesce(p_word, ''));
  f text;
  best text;
  low text;
  vowels text;
  i int;
  c text;
begin
  if w = '' or w ~ '[çğöşüÇĞÖŞÜ]' or w !~ '^[A-Za-zıİ]+$' then
    return w;
  end if;
  f := public._id_fold(w);
  -- Sözlük: oyuncu ad ve soyadlarındaki kelimeler (en sık yazım).
  select t.word into best
    from (
      select regexp_split_to_table(btrim(p.name), '\s+') as word from public.players p
      union all
      select regexp_split_to_table(btrim(p.surname), '\s+') from public.players p
    ) t
   where public._id_fold(t.word) = f
     and t.word ~ '^[A-ZÇĞİÖŞÜ][a-zçğıöşü]+$'
   group by t.word
   order by (t.word ~ '[çğöşüıiÇĞÖŞÜİ]') desc, count(*) desc, t.word
   limit 1;
  if best is not null then
    return best;
  end if;
  -- Sözlükte yok: Türkçe küçük harf, ı/i ünlü uyumuyla.
  low := replace(replace(w, 'I', 'ı'), 'İ', 'i');
  low := lower(low);
  vowels := regexp_replace(low, '[^aeıioöuü]', '', 'g');
  if position('ı' in low) > 0 then
    if regexp_replace(vowels, '[ıi]', '', 'g') ~ '^[eöü]+$' then
      low := replace(low, 'ı', 'i');
    end if;
  end if;
  c := left(low, 1);
  return case c when 'i' then 'İ' when 'ı' then 'I' else upper(c) end || substr(low, 2);
end;
$function$;

CREATE OR REPLACE FUNCTION public.tr_name_fix(p text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select string_agg(public.tr_name_word_fix(x.w), ' ' order by x.n)
    from regexp_split_to_table(btrim(coalesce(p, '')), '\s+') with ordinality as x(w, n)
   where x.w <> '';
$function$;

-- Kayıt: kimlikten gelen ad Türkçe harfleriyle yazılır.
CREATE OR REPLACE FUNCTION public.register_player(p_phone text, p_code text, p_password text, p_first text, p_last text, p_birth date, p_tc text, p_main text, p_sub text, p_foot text, p_height integer, p_weight integer)
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

  -- Aynı kişi: önce TC onayı, sonra numarası (kodla doğrulanır) kayıtlı
  -- profil, yoksa ad + soyad + doğum tarihi tutan onaysız profil.
  select v.player_id, p.auth_uid into v_player, v_auth
    from public.player_verifications v
    join public.players p on p.id = v.player_id
   where v.tc_hash = v_hash;
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
    -- Mevcut profil: kişinin kendi girdikleri ve kimlikteki bilgiler yazılır.
    -- Ad, soyad ve doğum tarihi kimlik çipindekiyle güncellenir. Ad yalnız
    -- gerçekten farklıysa değişir (Aktaş ↔ AKTAS gibi harf farkı değil).
    -- Aynı ad soyad ve tarihte başka profil varsa (players_identity_uq)
    -- profildeki kimlik bilgileri olduğu gibi kalır.
    select case when public._id_fold(p.name) = public._id_fold(v_first)
                then p.name else v_first end,
           case when public._id_fold(p.surname) = public._id_fold(v_last)
                then p.surname else v_last end
      into v_new_first, v_new_last
      from public.players p where p.id = v_player;
    if exists (select 1 from public.players o
                where o.id <> v_player
                  and public.norm_person_name(o.name::text)
                      = public.norm_person_name(v_new_first)
                  and public.norm_person_name(o.surname)
                      = public.norm_person_name(v_new_last)
                  and o.birth_date = p_birth) then
      select p.name, p.surname, p.birth_date into v_new_first, v_new_last, v_new_birth
        from public.players p where p.id = v_player;
    else
      v_new_birth := p_birth;
    end if;
    update public.players
       set phone = v_raw,
           name = v_new_first,
           surname = v_new_last,
           birth_date = v_new_birth,
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

-- Kod mesajı başlığı (Telegram) da düzeltilmiş adla.
CREATE OR REPLACE FUNCTION public.register_otp_send(p_phone text, p_kind text, p_name text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_raw text := public.phone_raw10(p_phone);
begin
  if not public.self_registration_enabled() then
    return 'disabled';
  end if;
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    return 'invalid_phone';
  end if;
  if exists (select 1 from auth.users where email = v_raw || '@masterclass.com') then
    return 'has_account';
  end if;
  return public._otp_issue(
    v_raw, 'register',
    case when p_kind = 'player' then 'Futbolcu kaydı' else 'Turnuva sorumlusu kaydı' end
      || coalesce(' · ' || nullif(left(coalesce(public.tr_name_fix(p_name), ''), 60), ''), '')
  );
end;
$function$;

-- identity_add_to_roster: kimlikle eklenen yeni oyuncunun adı.
CREATE OR REPLACE FUNCTION public.identity_add_to_roster(p_match_id uuid, p_team_id uuid, p_first text, p_last text, p_birth date, p_tc text, p_player_id uuid DEFAULT NULL::uuid, p_jersey smallint DEFAULT NULL::smallint, p_display text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  m public.matches;
  v_staff boolean;
  v_hash text;
  v_player uuid := p_player_id;
  v_first text := coalesce(public.tr_name_fix(p_first), '');
  v_last text := coalesce(public.tr_name_fix(p_last), '');
  v_disp text[];
  v_cur public.season_team_players;
  v_name text;
begin
  perform public._identity_guard(p_tc);
  select * into m from public.matches where id = p_match_id;
  if not found then
    raise exception 'Maç bulunamadı.';
  end if;
  if p_team_id not in (m.home_team_id, m.away_team_id) then
    raise exception 'Takım bu maçta değil.';
  end if;
  v_staff := public.owns_season_team(m.season_id, p_team_id);
  if not v_staff and not public.attendance_is_manager(m.season_id, p_team_id) then
    raise exception 'Bu takıma oyuncu ekleme yetkiniz yok.';
  end if;
  v_hash := public._identity_hash(p_tc);

  if v_player is not null then
    -- Seçilen mevcut profil kimlikle onaylanır (kurallar identity_verify'da).
    perform public.identity_verify(v_player, p_first, p_last, p_birth, p_tc);
  else
    select player_id into v_player
      from public.player_verifications where tc_hash = v_hash;
    if v_player is null then
      -- Çip adı Türkçe harf taşımaz; kağıttaki yazım aynı harflerse o kullanılır.
      v_disp := regexp_split_to_array(trim(coalesce(p_display, '')), '\s+');
      if array_length(v_disp, 1) >= 2
         and public._id_fold(array_to_string(v_disp[1:array_length(v_disp, 1) - 1], ' '))
             = public._id_fold(trim(p_first))
         and public._id_fold(v_disp[array_length(v_disp, 1)]) = public._id_fold(trim(p_last)) then
        v_first := array_to_string(v_disp[1:array_length(v_disp, 1) - 1], ' ');
        v_last := v_disp[array_length(v_disp, 1)];
      end if;
      insert into public.players (name, surname, birth_date)
      values (v_first, v_last, p_birth)
      returning id into v_player;
      insert into public.player_verifications (player_id, tc_hash, verified_by)
      values (v_player, v_hash, auth.uid());
      insert into public.identity_events (player_id, action, user_id)
      values (v_player, 'create', auth.uid()), (v_player, 'verify', auth.uid());
    end if;
  end if;

  select trim(coalesce(name, '') || ' ' || coalesce(surname, '')) into v_name
    from public.players where id = v_player;

  select * into v_cur from public.season_team_players
   where season_id = m.season_id and player_id = v_player
   order by is_active desc limit 1;
  if found and v_cur.is_active and v_cur.team_id <> p_team_id then
    raise exception '% bu sezon başka bir takımda kayıtlı.', v_name;
  end if;
  if found and v_cur.is_active then
    return jsonb_build_object('status', 'added', 'player_id', v_player, 'name', v_name);
  end if;

  if v_staff then
    if found then
      update public.season_team_players
         set team_id = p_team_id, is_active = true,
             jersey_number = coalesce(p_jersey, jersey_number)
       where id = v_cur.id;
    else
      insert into public.season_team_players (season_id, team_id, player_id, jersey_number, is_active)
      values (m.season_id, p_team_id, v_player, p_jersey, true);
    end if;
    return jsonb_build_object('status', 'added', 'player_id', v_player, 'name', v_name);
  end if;

  insert into public.pending_actions (action_type, season_id, team_id, payload)
  values ('roster_add', m.season_id, p_team_id, jsonb_build_object(
    'player_id', v_player, 'player_name', v_name,
    'match_id', p_match_id, 'jersey_number', p_jersey, 'via', 'identity'))
  on conflict do nothing;
  return jsonb_build_object('status', 'pending', 'player_id', v_player, 'name', v_name);
end;
$function$;

-- identity_add_to_season_roster: kimlikle eklenen yeni oyuncunun adı.
CREATE OR REPLACE FUNCTION public.identity_add_to_season_roster(p_season_id uuid, p_team_id uuid, p_first text, p_last text, p_birth date, p_tc text, p_player_id uuid DEFAULT NULL::uuid, p_jersey smallint DEFAULT NULL::smallint, p_display text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_staff boolean;
  v_hash text;
  v_player uuid := p_player_id;
  v_first text := coalesce(public.tr_name_fix(p_first), '');
  v_last text := coalesce(public.tr_name_fix(p_last), '');
  v_disp text[];
  v_cur public.season_team_players;
  v_name text;
begin
  perform public._identity_guard(p_tc);
  if not exists (select 1 from public.season_teams
                  where season_id = p_season_id and team_id = p_team_id) then
    raise exception 'Takım bu turnuvada değil.';
  end if;
  v_staff := public.owns_season_team(p_season_id, p_team_id);
  if not v_staff and not public.attendance_is_manager(p_season_id, p_team_id) then
    raise exception 'Bu takıma oyuncu ekleme yetkiniz yok.';
  end if;
  v_hash := public._identity_hash(p_tc);

  if v_player is not null then
    -- Seçilen mevcut profil kimlikle onaylanır (kurallar identity_verify'da).
    perform public.identity_verify(v_player, p_first, p_last, p_birth, p_tc);
  else
    select player_id into v_player
      from public.player_verifications where tc_hash = v_hash;
    if v_player is null then
      -- Çip adı Türkçe harf taşımaz; kağıttaki yazım aynı harflerse o kullanılır.
      v_disp := regexp_split_to_array(trim(coalesce(p_display, '')), '\s+');
      if array_length(v_disp, 1) >= 2
         and public._id_fold(array_to_string(v_disp[1:array_length(v_disp, 1) - 1], ' '))
             = public._id_fold(trim(p_first))
         and public._id_fold(v_disp[array_length(v_disp, 1)]) = public._id_fold(trim(p_last)) then
        v_first := array_to_string(v_disp[1:array_length(v_disp, 1) - 1], ' ');
        v_last := v_disp[array_length(v_disp, 1)];
      end if;
      insert into public.players (name, surname, birth_date)
      values (v_first, v_last, p_birth)
      returning id into v_player;
      insert into public.player_verifications (player_id, tc_hash, verified_by)
      values (v_player, v_hash, auth.uid());
      insert into public.identity_events (player_id, action, user_id)
      values (v_player, 'create', auth.uid()), (v_player, 'verify', auth.uid());
    end if;
  end if;

  select trim(coalesce(name, '') || ' ' || coalesce(surname, '')) into v_name
    from public.players where id = v_player;

  select * into v_cur from public.season_team_players
   where season_id = p_season_id and player_id = v_player
   order by is_active desc limit 1;
  if found and v_cur.is_active and v_cur.team_id <> p_team_id then
    raise exception '% bu sezon başka bir takımda kayıtlı.', v_name;
  end if;
  if found and v_cur.is_active then
    return jsonb_build_object('status', 'added', 'player_id', v_player, 'name', v_name);
  end if;

  if v_staff then
    if found then
      update public.season_team_players
         set team_id = p_team_id, is_active = true,
             jersey_number = coalesce(p_jersey, jersey_number)
       where id = v_cur.id;
    else
      insert into public.season_team_players (season_id, team_id, player_id, jersey_number, is_active)
      values (p_season_id, p_team_id, v_player, p_jersey, true);
    end if;
    return jsonb_build_object('status', 'added', 'player_id', v_player, 'name', v_name);
  end if;

  insert into public.pending_actions (action_type, season_id, team_id, payload)
  values ('roster_add', p_season_id, p_team_id, jsonb_build_object(
    'player_id', v_player, 'player_name', v_name,
    'jersey_number', p_jersey, 'via', 'identity'))
  on conflict do nothing;
  return jsonb_build_object('status', 'pending', 'player_id', v_player, 'name', v_name);
end;
$function$;

-- Kimlik doğrulama: ad gerçekten farklıysa düzeltilmiş adla güncellenir.
CREATE OR REPLACE FUNCTION public.identity_verify(p_player_id uuid, p_first text, p_last text, p_birth date, p_tc text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_hash text;
  p record;
  v_other record;
  v_wide boolean := public._identity_wide();
  v_name_ok boolean;
  v_wide_ok boolean;
begin
  perform public._identity_guard(p_tc);
  v_hash := public._identity_hash(p_tc);

  select * into p from public.players where id = p_player_id;
  if not found then
    raise exception 'Profil bulunamadı.';
  end if;

  v_name_ok := public._id_fold(p.surname) = public._id_fold(p_last)
     or split_part(public._id_fold(p.name), ' ', 1)
        = split_part(public._id_fold(p_first), ' ', 1);
  v_wide_ok := v_wide and (
       (public._id_fold(p.surname) = public._id_fold(p_last)
        and split_part(public._id_fold(p.name), ' ', 1)
            = split_part(public._id_fold(p_first), ' ', 1))
    or (extract(year from p.birth_date) = extract(year from p_birth)
        and extensions.levenshtein(
              split_part(public._id_fold(p.name), ' ', 1),
              split_part(public._id_fold(p_first), ' ', 1)) <= 1));

  if not v_wide_ok then
    if p.birth_date is distinct from p_birth then
      raise exception 'Kimlikteki doğum tarihi profille eşleşmiyor.';
    end if;
    if not v_name_ok then
      raise exception 'Kimlikteki ad soyad profille eşleşmiyor.';
    end if;
  end if;

  select v.player_id, pl.name, pl.surname into v_other
    from public.player_verifications v
    join public.players pl on pl.id = v.player_id
   where v.tc_hash = v_hash and v.player_id <> p_player_id;
  if found then
    raise exception 'Bu kimlik başka bir profile onaylı: % %.',
      v_other.name, v_other.surname;
  end if;
  if exists (select 1 from public.player_verifications
              where player_id = p_player_id and tc_hash <> v_hash) then
    raise exception 'Bu profil başka bir kimlikle onaylı. Önce onayın kaldırılması gerekir.';
  end if;

  if v_wide_ok then
    update public.players
       set birth_date = p_birth,
           name = case when public._id_fold(name) = public._id_fold(p_first)
                       then name else coalesce(public.tr_name_fix(p_first), '') end,
           surname = case when public._id_fold(surname) = public._id_fold(p_last)
                          then surname else coalesce(public.tr_name_fix(p_last), '') end
     where id = p_player_id
       and (birth_date is distinct from p_birth
            or public._id_fold(name) <> public._id_fold(p_first)
            or public._id_fold(surname) <> public._id_fold(p_last));
    if found then
      insert into public.identity_events (player_id, action, user_id)
      values (p_player_id,
              'correct: ' || coalesce(p.name, '') || ' ' || coalesce(p.surname, '')
                || ' ' || coalesce(p.birth_date::text, '-'),
              auth.uid());
    end if;
  end if;

  insert into public.player_verifications (player_id, tc_hash, verified_by)
  values (p_player_id, v_hash, auth.uid())
  on conflict (player_id) do nothing;
  insert into public.identity_events (player_id, action, user_id)
  values (p_player_id, 'verify', auth.uid());
end;
$function$;

-- Yalnız yukarıdaki (sahibinin yetkisiyle çalışan) fonksiyonlar kullanır.
revoke execute on function public.tr_name_word_fix(text) from public, anon, authenticated;
revoke execute on function public.tr_name_fix(text) from public, anon, authenticated;
