-- Elle futbolcu ekleme parametresi + kimlik önerisinin admin/kurucu başkan
-- için genişletilmesi.

-- 1) app_settings.manual_player_create_enabled (varsayılan açık). Kapalıyken
--    yalnız admin yeni futbolcu açabilir; diğerleri listeden seçer. Kendi
--    kaydı (register_player) bu ayardan etkilenmez.
insert into public.app_settings (key, value)
values ('manual_player_create_enabled', 'true'::jsonb)
on conflict (key) do nothing;

create or replace function public.manual_player_create_allowed()
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.is_admin()
      or coalesce((select value <> 'false'::jsonb from public.app_settings
                    where key = 'manual_player_create_enabled'), true);
$$;
grant execute on function public.manual_player_create_allowed() to authenticated;

drop policy if exists players_insert on public.players;
create policy players_insert on public.players
  for insert to authenticated
  with check (
    (public.is_admin() or public.is_any_league_owner() or public.is_any_region_owner())
    and public.manual_player_create_allowed()
  );

CREATE OR REPLACE FUNCTION public.staff_create_player(p_name text, p_surname text, p_birth date, p_phone text DEFAULT NULL::text, p_main text DEFAULT NULL::text, p_foot text DEFAULT NULL::text, p_height integer DEFAULT NULL::integer, p_weight integer DEFAULT NULL::integer, p_sub text DEFAULT NULL::text, p_photo text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if not public.manual_player_create_allowed() then
    raise exception 'Yeni futbolcu ekleme kapalı. Futbolcu uygulamadan kayıt olsun; sonra listeden seçin.';
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

  -- Tüm bilgiler tek seferde: kadroya eklenmemiş oyuncuyu kurucu başkan
  -- sonradan güncelleyemez (owns_player).
  insert into public.players (
    name, surname, birth_date, phone, main_position, sub_position,
    preferred_foot, height, weight, photo_url
  ) values (
    trim(p_name), nullif(trim(coalesce(p_surname, '')), ''), p_birth, v_raw,
    nullif(trim(coalesce(p_main, '')), ''), nullif(trim(coalesce(p_sub, '')), ''),
    nullif(trim(coalesce(p_foot, '')), ''), p_height, p_weight,
    nullif(trim(coalesce(p_photo, '')), '')
  ) returning id into v_id;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.review_pending_action(p_action_id uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  a         public.pending_actions;
  v_player  uuid;
  v_jersey  smallint;
  v_p       jsonb;
  v_current public.season_team_players;
begin
  select * into a from public.pending_actions
  where id = p_action_id
  for update;

  if not found then
    raise exception 'Talep bulunamadı.';
  end if;
  if not (public.owns_league(a.league_id)
          or public.owns_season_team(a.season_id, a.team_id)) then
    raise exception 'Bu talebi inceleme yetkiniz yok.';
  end if;
  if a.status <> 'pending' then
    raise exception 'Talep zaten sonuçlanmış (%).', a.status;
  end if;

  if p_approve then
    v_player := nullif(a.payload ->> 'player_id', '')::uuid;
    v_jersey := nullif(a.payload ->> 'jersey_number', '')::smallint;

    if a.action_type = 'roster_add' then
      if v_player is null then
        v_p := a.payload -> 'player';
        if v_p is null
           or coalesce(trim(v_p ->> 'name'), '') = ''
           or coalesce(trim(v_p ->> 'surname'), '') = ''
           or nullif(v_p ->> 'birth_date', '') is null then
          raise exception 'Yeni oyuncu için ad, soyad ve doğum tarihi gerekli.';
        end if;
        if not public.manual_player_create_allowed() then
          raise exception 'Yeni futbolcu ekleme kapalı. Futbolcu uygulamadan kayıt olsun; sonra listeden seçin.';
        end if;
        insert into public.players (
          name, surname, birth_date, phone, main_position, preferred_foot
        ) values (
          trim(v_p ->> 'name'),
          trim(v_p ->> 'surname'),
          (v_p ->> 'birth_date')::date,
          public.phone_raw10(v_p ->> 'phone'),
          nullif(trim(v_p ->> 'main_position'), ''),
          nullif(trim(v_p ->> 'preferred_foot'), '')
        )
        returning id into v_player;
      end if;

      select * into v_current from public.season_team_players
      where season_id = a.season_id and player_id = v_player;

      if found and v_current.is_active and v_current.team_id <> a.team_id then
        raise exception 'Oyuncu bu sezon başka bir takımda kayıtlı.';
      end if;

      if found then
        update public.season_team_players
        set team_id = a.team_id,
            is_active = true,
            jersey_number = coalesce(v_jersey, jersey_number)
        where id = v_current.id;
      else
        insert into public.season_team_players (
          season_id, team_id, player_id, jersey_number, is_active
        ) values (a.season_id, a.team_id, v_player, v_jersey, true);
      end if;

    elsif a.action_type = 'roster_remove' then
      update public.season_team_players
      set is_active = false
      where season_id = a.season_id
        and team_id = a.team_id
        and player_id = v_player;
      if not found then
        raise exception 'Oyuncu bu takımın kadrosunda değil.';
      end if;

    elsif a.action_type = 'jersey_change' then
      if v_jersey is not null and exists (
        select 1 from public.season_team_players
        where season_id = a.season_id and team_id = a.team_id
          and jersey_number = v_jersey and is_active
          and player_id <> v_player
      ) then
        raise exception 'Bu forma numarası takımda kullanılıyor.';
      end if;
      update public.season_team_players
      set jersey_number = v_jersey
      where season_id = a.season_id
        and team_id = a.team_id
        and player_id = v_player
        and is_active;
      if not found then
        raise exception 'Oyuncu bu takımın aktif kadrosunda değil.';
      end if;
    end if;
  end if;

  update public.pending_actions
  set status = case when p_approve then 'approved' else 'rejected' end,
      review_note = p_note,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      payload = case
        when p_approve and a.action_type = 'roster_add' and v_player is not null
          then payload || jsonb_build_object('player_id', v_player)
        else payload
      end
  where id = a.id;
end;
$function$;

-- 2) Kimlik önerisi: admin ve kurucu başkan için iki geniş aday türü.
--    'year': ad + soyad tutuyor, doğum tarihi (yılı) farklı.
--    'name': ad (1 harf farkla) + doğum yılı tutuyor; yalnız tam eşleşme
--            (tc/exact/year) hiç yoksa.
--    Diğer kullanıcılar eskisi gibi yalnız aynı doğum tarihli adayları görür.
create extension if not exists fuzzystrmatch with schema extensions;

-- Kimlik eşleştirmesi için ASCII sadeleştirme: çip (MRZ) adları Türkçe harf
-- taşımaz ("ÇELEBİ" → "CELEBI"); tr_fold "I"yı "ı" yaptığından tutmuyordu.
create or replace function public._id_fold(p text)
returns text
language sql
immutable
set search_path to ''
as $$
  select lower(translate(coalesce(p, ''),
                         'ÇĞİIÖŞÜÂÎÛçğıöşüâîû',
                         'CGIIOSUAIUcgiosuaiu'))
$$;


create or replace function public._identity_wide()
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.is_admin() or public.is_any_league_owner();
$$;

create or replace function public.identity_candidates(p_first text, p_last text, p_birth date, p_tc text)
 returns table(player_id uuid, name text, surname text, birth_date date, photo_url text, teams text, match_kind text, verified boolean)
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_hash text;
  v_first text := public._id_fold(p_first);
  v_first1 text := split_part(public._id_fold(p_first), ' ', 1);
  v_last text := public._id_fold(p_last);
  v_wide boolean := public._identity_wide();
begin
  perform public._identity_guard(p_tc);
  insert into public.identity_events (action, user_id)
  values ('lookup', auth.uid());
  v_hash := public._identity_hash(p_tc);

  return query
  with base as (
    select p.*, v.tc_hash,
           public._id_fold(p.surname) as f_last,
           public._id_fold(p.name) as f_first,
           split_part(public._id_fold(p.name), ' ', 1) as f_first1
      from public.players p
      left join public.player_verifications v on v.player_id = p.id
  ),
  c as (
    select b.*,
           case
             when b.tc_hash = v_hash then 'tc'
             when b.birth_date = p_birth
                  and b.f_last = v_last
                  and (b.f_first = v_first
                       or v_first like b.f_first || ' %'
                       or b.f_first like v_first || ' %')
               then 'exact'
             when b.birth_date = p_birth then 'near'
             when b.f_last = v_last and b.f_first1 = v_first1 then 'year'
             else 'name'
           end as m
      from base b
     where b.tc_hash = v_hash
        or (b.birth_date = p_birth
            and (b.f_last = v_last or b.f_first1 = v_first1))
        or (v_wide and b.f_last = v_last and b.f_first1 = v_first1)
        or (v_wide
            and extract(year from b.birth_date) = extract(year from p_birth)
            and extensions.levenshtein(b.f_first1, v_first1) <= 1)
  ),
  strong as (
    select exists (select 1 from c where c.m in ('tc', 'exact', 'year')) as yes
  )
  select c.id, c.name::text, c.surname, c.birth_date, c.photo_url,
         (select string_agg(distinct t.name, ', ')
            from public.season_team_players stp
            join public.teams t on t.id = stp.team_id
           where stp.player_id = c.id and stp.is_active),
         c.m, c.tc_hash is not null and c.tc_hash <> v_hash
    from c, strong
   where c.m <> 'name' or not strong.yes
   order by case c.m when 'tc' then 0 when 'exact' then 1 when 'year' then 2
                     when 'near' then 3 else 4 end,
            c.surname, c.name
   limit 10;
end;
$function$;

-- 3) Onay: admin/kurucu başkan geniş eşleşmeyi de onaylayabilir; bu durumda
--    profilin doğum tarihi (ve ad/soyad harfçe farklıysa ad/soyad) kimlikten
--    düzeltilir. Kimlik verisi Türkçe karakter taşımadığından yalnız harfler
--    farklıysa ad değişir (Çelebi ile CELEBI aynı sayılır).
create or replace function public.identity_verify(p_player_id uuid, p_first text, p_last text, p_birth date, p_tc text)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
                       then name else initcap(lower(trim(p_first))) end,
           surname = case when public._id_fold(surname) = public._id_fold(p_last)
                          then surname else initcap(lower(trim(p_last))) end
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
