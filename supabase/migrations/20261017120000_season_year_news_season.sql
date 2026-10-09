-- 1) Sezon: başlangıç/bitiş zorunlu, season_year = başlangıç yılı, ad standardı
--    "<yıl> Sezonu" (otomatik). Sezon ve grup ekleme/silme ile grup adı
--    değiştirme yalnızca admin.
-- 2) Haberler turnuva yerine sezona bağlanır (news.season_id; league_id kalkar).

alter table public.seasons alter column start_date set not null;
alter table public.seasons alter column end_date set not null;
alter table public.seasons
  add column if not exists season_year integer
    generated always as (extract(year from start_date)::integer) stored;
create index if not exists seasons_league_year_idx
  on public.seasons (league_id, season_year);

create or replace function public.seasons_standard_name()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.name := extract(year from new.start_date)::integer || ' Sezonu';
  return new;
end;
$$;

drop trigger if exists seasons_standard_name on public.seasons;
create trigger seasons_standard_name
  before insert or update on public.seasons
  for each row execute function public.seasons_standard_name();

update public.seasons set name = name;

drop policy if exists seasons_write on public.seasons;
drop policy if exists seasons_insert on public.seasons;
drop policy if exists seasons_update on public.seasons;
drop policy if exists seasons_delete on public.seasons;
create policy seasons_insert on public.seasons for insert to authenticated
  with check (public.is_admin());
create policy seasons_update on public.seasons for update to authenticated
  using (public.owns_league(league_id)) with check (public.owns_league(league_id));
create policy seasons_delete on public.seasons for delete to authenticated
  using (public.is_admin());

drop policy if exists groups_write on public.groups;
drop policy if exists groups_insert on public.groups;
drop policy if exists groups_update on public.groups;
drop policy if exists groups_delete on public.groups;
create policy groups_insert on public.groups for insert to authenticated
  with check (public.is_admin());
create policy groups_update on public.groups for update to authenticated
  using (public.owns_season(season_id) or public.owns_region(region_id))
  with check (public.owns_season(season_id) or public.owns_region(region_id));
create policy groups_delete on public.groups for delete to authenticated
  using (public.is_admin());

create or replace function public.guard_group_name()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.name is distinct from old.name
     and coalesce(auth.role(), '') in ('authenticated', 'anon')
     and not public.is_admin() then
    raise exception 'Grup adını yalnızca admin değiştirebilir.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_group_name on public.groups;
create trigger guard_group_name
  before update of name on public.groups
  for each row execute function public.guard_group_name();

-- Turnuva adını da yalnızca admin değiştirir.
create or replace function public.guard_league_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.role(), '') in ('authenticated', 'anon')
     and not public.is_admin() then
    if new.status is distinct from old.status then
      raise exception 'Turnuva durumunu yalnızca admin değiştirebilir.'
        using errcode = '42501';
    end if;
    if new.transfer_enabled is distinct from old.transfer_enabled then
      raise exception 'Transfer ayarını yalnızca admin değiştirebilir.'
        using errcode = '42501';
    end if;
    if new.name is distinct from old.name then
      raise exception 'Turnuva adını yalnızca admin değiştirebilir.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

-- 2) Haberler → sezon.
alter table public.news
  add column if not exists season_id uuid references public.seasons (id) on delete cascade;

-- Bölgeli haber bölgenin sezonuna; diğerleri yayın tarihini kapsayan sezona,
-- yoksa turnuvanın en yeni sezonuna.
update public.news n set season_id = r.season_id
from public.season_regions r
where n.season_id is null and n.region_id = r.id;
update public.news n set season_id = (
  select s.id from public.seasons s
  where s.league_id = n.league_id
  order by (n.created_at::date between s.start_date and s.end_date) desc,
           s.start_date desc
  limit 1)
where n.season_id is null;

alter table public.news alter column season_id set not null;

drop policy if exists news_read on public.news;
drop policy if exists news_write on public.news;
drop trigger if exists set_updated_at on public.news;
alter table public.news drop column league_id;
drop function if exists public.owns_news(uuid, uuid);

create or replace function public.owns_news(p_season_id uuid, p_region_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.owns_season(p_season_id) or (
    p_region_id is not null and exists (
      select 1 from public.season_regions r
      join public.region_owners ro on ro.region_id = r.id
      where r.id = p_region_id and r.season_id = p_season_id
        and ro.user_id = auth.uid()
    )
  )
$$;

create policy news_read on public.news for select
  using (
    public.owns_news(season_id, region_id)
    or (is_published
        and (publish_until is null or publish_until > now())
        and public.can_view_season(season_id))
  );
create policy news_write on public.news for all to authenticated
  using (public.owns_news(season_id, region_id))
  with check (public.owns_news(season_id, region_id));

create trigger set_updated_at
  before update of season_id, content, is_published, image_url on public.news
  for each row execute function public.set_updated_at();

create index if not exists news_season_created_idx
  on public.news (season_id, created_at desc);

CREATE OR REPLACE FUNCTION public.news_push_notify()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ids uuid[];
  v_league text;
  v_league_id uuid;
begin
  if not coalesce(new.is_published, false) then
    return new;
  end if;
  if tg_op = 'UPDATE' and coalesce(old.is_published, false) then
    return new;
  end if;
  select s.league_id, l.name into v_league_id, v_league
  from public.seasons s join public.leagues l on l.id = s.league_id
  where s.id = new.season_id;
  if v_league_id is null then
    return new;
  end if;

  with ids as (
    select p.auth_uid as uid
    from public.season_team_players stp
    join public.seasons s on s.id = stp.season_id and s.is_active
    join public.players p on p.id = stp.player_id
    where s.league_id = v_league_id and stp.is_active
    union
    select tm.user_id from public.team_managers tm
    join public.seasons s on s.id = tm.season_id and s.is_active
    where s.league_id = v_league_id
    union
    select o.user_id from public.league_owners o where o.league_id = v_league_id
    union
    select f.user_id from public.league_followers f where f.league_id = v_league_id
  )
  select array_agg(distinct uid) into v_ids from ids where uid is not null;

  perform public.push_send(
    v_ids,
    coalesce(v_league, 'Turnuva') || ' · Yeni haber',
    left(regexp_replace(coalesce(new.content, ''), '\s+', ' ', 'g'), 120),
    '/',
    'news-' || new.id
  );
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_live_draw(p_league_id uuid, p_season_id uuid, p_group_id uuid, p_title text, p_start_week integer, p_start_at timestamp with time zone, p_team_ids uuid[], p_steps jsonb, p_byes jsonb, p_news_content text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
  v_total integer := jsonb_array_length(coalesce(p_steps, '[]'::jsonb));
  v_last numeric;
  v_start timestamptz := greatest(coalesce(p_start_at, now()), now());
begin
  if not (public.owns_league(p_league_id) or public.owns_season(p_season_id)) then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.seasons s
                 where s.id = p_season_id and s.league_id = p_league_id)
     or not exists (select 1 from public.groups g
                    where g.id = p_group_id and g.season_id = p_season_id) then
    raise exception 'Sezon / grup bu turnuvaya ait değil.';
  end if;
  if v_total = 0 then
    raise exception 'Kurada eşleşme yok.';
  end if;
  if exists (select 1 from public.matches where group_id = p_group_id) then
    raise exception 'Bu gruba maç girilmiş; kura çekilemez.';
  end if;
  if exists (select 1 from public.live_draws
             where group_id = p_group_id and status = 'scheduled') then
    raise exception 'Bu grup için planlanmış bir canlı kura zaten var.';
  end if;

  select max((s->>'at')::numeric) into v_last
  from jsonb_array_elements(p_steps) s;

  insert into public.live_draws (
    league_id, season_id, group_id, title, start_week, team_ids, steps, byes,
    total_matches, start_at, end_at
  ) values (
    p_league_id, p_season_id, p_group_id, left(trim(p_title), 160),
    greatest(coalesce(p_start_week, 1), 1), p_team_ids, p_steps,
    coalesce(p_byes, '[]'::jsonb), v_total, v_start,
    v_start + make_interval(secs => coalesce(v_last, 0) + 2)
  ) returning id into v_id;

  insert into public.news (season_id, content, is_published, live_draw_id)
  values (p_season_id, p_news_content, true, v_id);

  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.demo_reset()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  c_user constant uuid := 'd0000000-0000-4000-8000-0000000000aa';
  c_phone constant text := '5000000000';
  c_password constant text := 'demo2026';
  c_l1 constant uuid := 'd0000000-0000-4000-8000-000000000001';
  c_l2 constant uuid := 'd0000000-0000-4000-8000-000000000002';
  c_stream constant text := 'https://www.youtube.com/live/U_cmG_3xPxg';
  c_names_adult constant text[] := array[
    'Ahmet','Mehmet','Mustafa','Ali','Hüseyin','Hasan','İbrahim','Murat',
    'Ömer','Yusuf','Emre','Burak','Serkan','Volkan','Kemal','Erkan','Tolga',
    'Cem','Barış','Onur','Selim','Okan','Levent','Hakan','Tuncay','Sinan',
    'Gökhan','Ercan','Taner','Engin','Caner','Uğur','Fatih','Kaan','Orhan',
    'Bülent','Cengiz','Halil','Zafer','İlker'];
  c_names_kid constant text[] := array[
    'Efe','Arda','Kerem','Eymen','Yiğit','Mert','Berat','Ege','Doruk','Alp',
    'Çınar','Aras','Poyraz','Ömer','Emir','Miraç','Kuzey','Atlas','Deniz',
    'Batuhan','Yusuf','Kaan','Eren','Tuna'];
  v_teams uuid[];
  v_players uuid[];
  v_last_sat date;
  v_s1 uuid;
  v_s2 uuid;
  v_r1 uuid;
  v_r2 uuid;
  v_txt text;
  v_txt2 text;
begin
  perform setseed(0.2026);

  -- 1) Eski demo verisini sil (yalnızca demo sezonlarında yer alan takım ve
  --    oyuncular; demo hesabının sonradan eklediği kayıtlar da gider).
  select coalesce(array_agg(distinct st.team_id), '{}') into v_teams
  from public.season_teams st
  join public.seasons s on s.id = st.season_id
  where s.league_id in (c_l1, c_l2)
    and not exists (
      select 1 from public.season_teams x
      join public.seasons y on y.id = x.season_id
      where x.team_id = st.team_id and y.league_id not in (c_l1, c_l2));
  select coalesce(array_agg(distinct stp.player_id), '{}') into v_players
  from public.season_team_players stp
  join public.seasons s on s.id = stp.season_id
  where s.league_id in (c_l1, c_l2)
    and not exists (
      select 1 from public.season_team_players x
      join public.seasons y on y.id = x.season_id
      where x.player_id = stp.player_id and y.league_id not in (c_l1, c_l2));

  delete from public.matches where league_id in (c_l1, c_l2)
    or season_id in (select id from public.seasons where league_id in (c_l1, c_l2));
  delete from public.seasons where league_id in (c_l1, c_l2);
  delete from public.teams where id = any(v_teams);
  delete from public.players where id = any(v_players) and auth_uid is null;
  delete from public.leagues where id in (c_l1, c_l2);

  -- 2) Demo Başkan hesabı (telefon 500 000 00 00).
  if not exists (select 1 from auth.users where id = c_user) then
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, recovery_token,
      email_change_token_new, email_change)
    values (
      '00000000-0000-0000-0000-000000000000', c_user, 'authenticated',
      'authenticated', c_phone || '@masterclass.com',
      extensions.crypt(c_password, extensions.gen_salt('bf')), now(),
      '{"provider": "email", "providers": ["email"]}'::jsonb,
      '{"email_verified": true, "must_change_password": false, "name": "Demo Başkan"}'::jsonb,
      now(), now(), '', '', '', '');
    insert into auth.identities (
      provider_id, user_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at)
    values (
      c_user::text, c_user,
      jsonb_build_object('sub', c_user::text,
                         'email', c_phone || '@masterclass.com',
                         'email_verified', false, 'phone_verified', false),
      'email', now(), now(), now());
  else
    update auth.users
       set encrypted_password = extensions.crypt(c_password, extensions.gen_salt('bf')),
           raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
             || '{"must_change_password": false, "name": "Demo Başkan"}'::jsonb,
           updated_at = now()
     where id = c_user;
  end if;
  insert into public.app_users (phone, name, auth_uid, role)
  values (c_phone, 'Demo Başkan', c_user::text, 'player')
  on conflict (phone) do update
    set auth_uid = excluded.auth_uid, name = excluded.name;

  -- 3) Turnuvalar (bildirim tetikleyicileri kurulum boyunca kapalı).
  alter table public.matches disable trigger matches_push_notify;
  alter table public.news disable trigger news_push_notify;

  insert into public.leagues (
    id, name, short_name, is_private, is_demo, access_code, is_active,
    theme_primary, theme_secondary, roster_open_hours)
  values
    (c_l1, 'Demo Masterlar Ligi', 'Demo Masterlar', true, true, '730415',
     true, '#0F3D2E', '#E0A526', 1),
    (c_l2, 'Demo Okul Kupası', 'Demo Okul Kupası', true, true, '730416',
     true, '#1D4ED8', '#F59E0B', 1);
  insert into public.league_owners (league_id, user_id)
  values (c_l1, c_user), (c_l2, c_user);

  -- Son oynanan hafta: bugünden önceki son cumartesi.
  v_last_sat := current_date
    - case when extract(isodow from current_date)::int = 6 then 7
           else (extract(isodow from current_date)::int + 1) % 7 end;

  v_s1 := public._demo_build_season(
    c_l1, '2026-2027 Sezonu',
    array['Avrupa Yakası', 'Anadolu Yakası'],
    array['Avrupa Grubu', 'Anadolu Grubu'],
    array['Kuzey Yıldızları', 'Galata Veteranlar', 'Bakırköy Dostluk',
          'Florya Kartalları', 'Şişli Efsaneler', 'Eyüp Sultanlar',
          'Beylikdüzü Masterlar', 'Haliç Spor',
          'Moda Masterlar', 'Üsküdar Dostlar', 'Ataşehir Yıldızları',
          'Maltepe Sahil', 'Kartal Veteranlar', 'Pendik Denizciler',
          'Çekmeköy Kurtları', 'Beykoz Efsaneleri'],
    8, 11, 30, 5, 4, v_last_sat - 21,
    array['19:00', '20:00', '21:00', '22:00'],
    array['415c9143-c7d0-4539-a276-e413ecf25c23'::uuid,
          'c9dd6c7d-29fe-49b9-813c-d91524e7666d'::uuid],
    1976, 1988, c_names_adult, '4-4-2', c_stream);

  v_s2 := public._demo_build_season(
    c_l2, '2026-2027 Sezonu', null,
    array['A Grubu'],
    array['Yıldız Koleji', 'Bilim Ortaokulu', 'Deniz Anadolu Lisesi',
          'Çınar Koleji', 'Ufuk Ortaokulu', 'Gökkuşağı Koleji'],
    6, 7, 20, 5, 2, v_last_sat - 7,
    array['10:00', '11:00', '12:00'],
    array['5c305a3a-574a-410b-a555-2642e187044f'::uuid],
    2011, 2013, c_names_kid, '2-3-1', c_stream);

  -- 4) Haberler (sonuçlardan üretilir).
  select id into v_r1 from public.season_regions where season_id = v_s1 and sort_order = 1;
  select id into v_r2 from public.season_regions where season_id = v_s1 and sort_order = 2;

  select string_agg(h.name || ' ' || m.home_score || '-' || m.away_score || ' ' || a.name,
                    E'\n' order by m.match_time)
    into v_txt
  from public.matches m
  join public.teams h on h.id = m.home_team_id
  join public.teams a on a.id = m.away_team_id
  join public.groups g on g.id = m.group_id
  where m.season_id = v_s1 and m.week = 4 and g.region_id = v_r1;
  insert into public.news (season_id, region_id, content, is_published, created_at)
  values (v_s1, v_r1,
    'AVRUPA GRUBUNDA 4. HAFTA TAMAMLANDI' || E'\n\n' || v_txt || E'\n\n' ||
    'Avrupa Grubu''nda dördüncü hafta geride kaldı. Puan durumu ve gol krallığı '
    || 'uygulamada güncellendi. Gelecek hafta görüşmek üzere!',
    true, (v_last_sat + 1)::timestamp + interval '10 hours');

  select string_agg(h.name || ' ' || m.home_score || '-' || m.away_score || ' ' || a.name,
                    E'\n' order by m.match_time)
    into v_txt
  from public.matches m
  join public.teams h on h.id = m.home_team_id
  join public.teams a on a.id = m.away_team_id
  join public.groups g on g.id = m.group_id
  where m.season_id = v_s1 and m.week = 4 and g.region_id = v_r2;
  insert into public.news (season_id, region_id, content, is_published, created_at)
  values (v_s1, v_r2,
    'ANADOLU GRUBUNDA 4. HAFTA SONUÇLARI' || E'\n\n' || v_txt || E'\n\n' ||
    'Anadolu Grubu''nda heyecan sürüyor. Maç özetleri ve kadrolar için maç '
    || 'detaylarına göz atabilirsiniz.',
    true, (v_last_sat + 1)::timestamp + interval '11 hours');

  -- Zirvedeki golcü(ler); beraberlikte hepsi yazılır.
  with c as (
    select p.name || ' ' || p.surname || ' (' || t.name || ')' as who,
           count(*) as n
    from public.match_events e
    join public.players p on p.id = e.player_id
    join public.teams t on t.id = e.team_id
    where e.season_id = v_s1 and e.event_type = 'goal'
    group by p.id, p.name, p.surname, t.name
  ), top as (
    select * from c where n = (select max(n) from c)
  )
  select case when count(*) = 1
           then 'zirvede ' || max(who) || ' ' || max(n) || ' golle tek başına'
           else max(n) || ' golle ' || regexp_replace(
                  string_agg(who, ', ' order by who), ', ([^,]*)$', ' ve \1')
                || ' zirveyi paylaşıyor'
         end
    into v_txt
  from top;
  select h.name || ' ' || m.home_score || '-' || m.away_score || ' ' || a.name
    into v_txt2
  from public.matches m
  join public.teams h on h.id = m.home_team_id
  join public.teams a on a.id = m.away_team_id
  where m.season_id = v_s1 and m.status = 'finished'
  order by m.home_score + m.away_score desc, m.match_date desc limit 1;
  insert into public.news (season_id, content, is_published, created_at)
  values (v_s1,
    'GOL KRALLIĞINDA ZİRVE' || E'\n\n' || 'Dört haftanın ardından gol '
    || 'krallığında ' || v_txt || '. Sezonun en gollü maçı ise '
    || v_txt2 || ' karşılaşması oldu.',
    true, (v_last_sat + 2)::timestamp + interval '9 hours');

  insert into public.news (season_id, content, is_published, created_at)
  values (v_s1,
    '5. HAFTA PROGRAMI AÇIKLANDI' || E'\n\n' || 'Beşinci hafta maçları '
    || 'cumartesi günü oynanacak. Takım sorumluları esamelerini maç '
    || 'saatinden 1 saat önce uygulamadan girebilir. Cezalı oyuncular esamede '
    || 'işaretli görünür.',
    true, (v_last_sat + 2)::timestamp + interval '12 hours');

  insert into public.news (season_id, content, is_published, created_at)
  values (v_s1,
    'FAIR PLAY ÇAĞRISI' || E'\n\n' || 'Ligimizde dostluk ve centilmenlik '
    || 'her şeyden önce gelir. Hakem kararlarına saygı gösteren, rakibine '
    || 'yardım eden tüm oyuncularımıza teşekkür ederiz.',
    true, (v_last_sat - 3)::timestamp + interval '15 hours');

  select string_agg(h.name || ' ' || m.home_score || '-' || m.away_score || ' ' || a.name,
                    E'\n' order by m.match_time)
    into v_txt
  from public.matches m
  join public.teams h on h.id = m.home_team_id
  join public.teams a on a.id = m.away_team_id
  where m.season_id = v_s2 and m.week = 2;
  insert into public.news (season_id, content, is_published, created_at)
  values (v_s2,
    'OKUL KUPASI''NDA 2. HAFTA' || E'\n\n' || v_txt || E'\n\n' ||
    'Öğrencilerimizi ve onları destekleyen ailelere teşekkür ederiz.',
    true, (v_last_sat + 1)::timestamp + interval '13 hours');
  insert into public.news (season_id, content, is_published, created_at)
  values (v_s2,
    'OKUL KUPASI BAŞLADI' || E'\n\n' || 'Altı okulun katıldığı turnuvamız '
    || 'başladı. Maç programı, kadrolar ve sonuçlar uygulamada.',
    true, (v_last_sat - 8)::timestamp + interval '10 hours');

  alter table public.matches enable trigger matches_push_notify;
  alter table public.news enable trigger news_push_notify;

  return jsonb_build_object(
    'leagues', array[c_l1, c_l2],
    'login', c_phone, 'password', c_password,
    'matches', (select count(*) from public.matches where league_id in (c_l1, c_l2)),
    'events', (select count(*) from public.match_events e
               join public.matches m on m.id = e.match_id
               where m.league_id in (c_l1, c_l2)),
    'penalties', (select count(*) from public.player_penalties pp
                  where pp.season_id in (v_s1, v_s2)));
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_purge_league(p_league_id uuid, p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_seasons uuid[];
  v_teams uuid[];
  v_regions uuid[];
  v_news uuid[];
  v_matches uuid[];
  v_counts jsonb;
begin
  if not public.is_admin() then
    raise exception 'Yetkisiz';
  end if;
  if not exists (
    select 1 from public.leagues where id = p_league_id and status = 'passive'
  ) then
    raise exception 'Turnuva önce pasife alınmalı (status = passive)';
  end if;

  select coalesce(array_agg(id), '{}') into v_seasons
    from public.seasons where league_id = p_league_id;
  select coalesce(array_agg(id), '{}') into v_regions
    from public.season_regions where season_id = any(v_seasons);
  select coalesce(array_agg(id), '{}') into v_news
    from public.news where season_id = any(v_seasons);
  select coalesce(array_agg(id), '{}') into v_matches
    from public.matches where league_id = p_league_id;

  -- Yalnızca bu turnuvanın sezonlarında geçen takımlar; başka yerde kullanılanlar kalır.
  select coalesce(array_agg(distinct st.team_id), '{}') into v_teams
    from public.season_teams st
    where st.season_id = any(v_seasons)
      and not exists (
        select 1 from public.season_teams o
        where o.team_id = st.team_id and o.season_id <> all(v_seasons))
      and not exists (
        select 1 from public.season_registrations r
        where r.team_id = st.team_id and r.season_id <> all(v_seasons))
      and not exists (
        select 1 from public.matches m
        where (m.home_team_id = st.team_id or m.away_team_id = st.team_id)
          and m.season_id <> all(v_seasons))
      and not exists (
        select 1 from public.team_managers tm
        where tm.team_id = st.team_id and tm.season_id <> all(v_seasons));

  v_counts := jsonb_build_object(
    'seasons', (select count(*) from public.seasons where id = any(v_seasons)),
    'groups', (select count(*) from public.groups where season_id = any(v_seasons)),
    'season_regions', (select count(*) from public.season_regions where id = any(v_regions)),
    'region_owners', (select count(*) from public.region_owners where region_id = any(v_regions)),
    'region_owner_invites', (select count(*) from public.region_owner_invites where region_id = any(v_regions)),
    'season_teams', (select count(*) from public.season_teams where season_id = any(v_seasons)),
    'season_team_players', (select count(*) from public.season_team_players where season_id = any(v_seasons)),
    'season_registrations', (select count(*) from public.season_registrations where season_id = any(v_seasons)),
    'team_managers', (select count(*) from public.team_managers where season_id = any(v_seasons)),
    'player_season_stats', (select count(*) from public.player_season_stats where season_id = any(v_seasons)),
    'player_penalties', (select count(*) from public.player_penalties where season_id = any(v_seasons)),
    'matches', (select count(*) from public.matches where id = any(v_matches)),
    'match_rosters', (select count(*) from public.match_rosters where match_id = any(v_matches)),
    'match_events', (select count(*) from public.match_events where match_id = any(v_matches)),
    'match_media', (select count(*) from public.match_media where match_id = any(v_matches)),
    'live_draws', (select count(*) from public.live_draws where league_id = p_league_id),
    'news', (select count(*) from public.news where id = any(v_news)),
    'news_likes', (select count(*) from public.news_likes where news_id = any(v_news)),
    'awards', (select count(*) from public.awards where league_id = p_league_id),
    'sponsors', (select count(*) from public.sponsors where league_id = p_league_id),
    'league_owners', (select count(*) from public.league_owners where league_id = p_league_id),
    'league_owner_invites', (select count(*) from public.league_owner_invites where league_id = p_league_id),
    'league_followers', (select count(*) from public.league_followers where league_id = p_league_id),
    'pending_actions', (select count(*) from public.pending_actions where league_id = p_league_id),
    'teams', cardinality(v_teams)
  );

  if p_dry_run then
    return jsonb_build_object('dry_run', true, 'counts', v_counts);
  end if;

  delete from public.matches where id = any(v_matches);
  delete from public.seasons where id = any(v_seasons);
  delete from public.teams where id = any(v_teams);
  delete from public.leagues where id = p_league_id;

  return jsonb_build_object('dry_run', false, 'counts', v_counts);
end;
$function$;
