-- ============================================================================
-- Otomatik maç sonucu haberi
--
-- 1) leagues.auto_result_news : turnuva bazında aç/kapa (yalnız admin değiştirir)
-- 2) news.auto_kind/match_id/week/auto_data/auto_hidden
--      match_result : maç "Bitti" olunca tek maçın skor kartı (A)
--      week_results : haftanın (bölgenin) tüm maçları bitince toplu özet (C)
-- 3) refresh_result_news(match) : haberi oluşturur / günceller / gizler
-- 4) Tetikleyiciler: matches (durum, skor, hafta, silme) ve match_events (gol)
-- 5) Otomatik haberler bildirim göndermez.
--
-- Haber metni (content) eski uygulama sürümlerinde düz haber olarak görünür;
-- yeni sürüm kartı auto_data'dan çizer.
-- ============================================================================

-- 1) Turnuva ayarı
alter table public.leagues
  add column if not exists auto_result_news boolean not null default true;

create or replace function public.guard_league_status()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
    if new.auto_result_news is distinct from old.auto_result_news then
      raise exception 'Otomatik maç sonucu haberi ayarını yalnızca admin değiştirebilir.'
        using errcode = '42501';
    end if;
    if new.name is distinct from old.name then
      raise exception 'Turnuva adını yalnızca admin değiştirebilir.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$function$;

-- 2) Haber sütunları
alter table public.news
  add column if not exists auto_kind text
    check (auto_kind in ('match_result', 'week_results')),
  add column if not exists match_id uuid
    references public.matches (id) on delete cascade,
  add column if not exists week integer,
  add column if not exists auto_data jsonb,
  -- Sistem gizlediyse true; maç yeniden bitince haber geri açılır. Yöneticinin
  -- elle gizlediği haber (auto_hidden = false) kendiliğinden açılmaz.
  add column if not exists auto_hidden boolean not null default false;

create unique index if not exists news_auto_match_uq
  on public.news (match_id) where auto_kind = 'match_result';
create unique index if not exists news_auto_week_uq
  on public.news (season_id, coalesce(region_id, '00000000-0000-0000-0000-000000000000'::uuid), week)
  where auto_kind = 'week_results';

-- 3a) Tek maçın kart verisi
create or replace function public.match_result_data(p_match_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  with m as (
    select * from public.matches where id = p_match_id
  ),
  g as (
    -- Kendi kalesine gol rakip tarafa yazılır (team_id oyuncunun takımı).
    select
      case when e.is_own_goal
           then case when e.team_id = m.home_team_id then 'away' else 'home' end
           else case when e.team_id = m.home_team_id then 'home' else 'away' end
      end as side,
      coalesce(
        nullif(trim(concat_ws(' ', p.name, p.surname)), ''),
        nullif(trim(e.event_name), ''),
        'Gol'
      ) as name,
      e.player_id,
      coalesce(e.is_own_goal, false) as og,
      coalesce(e.is_penalty, false) as pen,
      e.minute,
      e.created_at
    from public.match_events e
    cross join m
    left join public.players p on p.id = e.player_id
    where e.match_id = p_match_id and e.event_type = 'goal'
  ),
  s as (
    select side, name, og,
           count(*)::int as n,
           count(*) filter (where pen)::int as pen,
           coalesce(jsonb_agg(minute order by minute) filter (where minute is not null), '[]'::jsonb) as minutes,
           min(coalesce(minute, 999)) as first_min,
           min(created_at) as first_at
    from g
    group by side, name, og, player_id
  ),
  t as (
    select id, name, logo_url, first_color from public.teams
  )
  select jsonb_build_object(
    'match_id', m.id,
    'week', m.week,
    'date', m.match_date,
    'home', jsonb_build_object('id', m.home_team_id, 'name', th.name,
                               'logo', th.logo_url, 'color', th.first_color),
    'away', jsonb_build_object('id', m.away_team_id, 'name', ta.name,
                               'logo', ta.logo_url, 'color', ta.first_color),
    'hs', coalesce(m.home_score, 0),
    'as', coalesce(m.away_score, 0),
    'scorers', jsonb_build_object(
      'home', coalesce((select jsonb_agg(jsonb_build_object(
                  'name', name, 'n', n, 'pen', pen, 'og', og, 'minutes', minutes)
                  order by first_min, first_at)
                from s where side = 'home'), '[]'::jsonb),
      'away', coalesce((select jsonb_agg(jsonb_build_object(
                  'name', name, 'n', n, 'pen', pen, 'og', og, 'minutes', minutes)
                  order by first_min, first_at)
                from s where side = 'away'), '[]'::jsonb)
    )
  )
  from m
  left join t th on th.id = m.home_team_id
  left join t ta on ta.id = m.away_team_id
$$;

-- 3b) Golcü listesi metni: "Ali Can (2), Veli Er (P), Mehmet Ak (K.K.)"
create or replace function public.result_scorers_text(p_list jsonb)
returns text
language sql
immutable
set search_path to ''
as $$
  select string_agg(
    (x->>'name')
      || case when (x->>'og')::boolean then ' (K.K.)' else '' end
      || case when (x->>'n')::int > 1 then ' (' || (x->>'n') || ')' else '' end
      || case when not (x->>'og')::boolean and (x->>'pen')::int > 0
              then case when (x->>'pen')::int = (x->>'n')::int and (x->>'n')::int = 1
                        then ' (P)' else ' (' || (x->>'pen') || ' P)' end
              else '' end,
    ', ' order by o)
  from jsonb_array_elements(coalesce(p_list, '[]'::jsonb)) with ordinality as a(x, o)
$$;

-- 3c) Tek satırlık sonuç metni (eski sürümler ve haftalık özet için)
create or replace function public.result_text(p jsonb)
returns text
language sql
immutable
set search_path to ''
as $$
  select concat_ws(E'\n',
    (p->'home'->>'name') || ' ' || (p->>'hs') || '-' || (p->>'as') || ' '
      || (p->'away'->>'name'),
    case when jsonb_array_length(p->'scorers'->'home') + jsonb_array_length(p->'scorers'->'away') > 0
         then 'Goller: ' || concat_ws(' · ',
                coalesce(public.result_scorers_text(p->'scorers'->'home'), '-'),
                coalesce(public.result_scorers_text(p->'scorers'->'away'), '-'))
    end)
$$;

-- 3d) Haftalık özet: (sezon, bölge, hafta) tamamlandıysa oluştur/güncelle
create or replace function public.refresh_week_results_news(
  p_season_id uuid, p_region_id uuid, p_week integer)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_enabled boolean;
  v_pending int;
  v_items jsonb;
  v_content text;
  v_id uuid;
  v_hidden boolean;
  v_published boolean;
begin
  if p_season_id is null or p_week is null then
    return;
  end if;
  select l.auto_result_news into v_enabled
    from public.seasons s join public.leagues l on l.id = s.league_id
   where s.id = p_season_id;

  -- Bekleyen maç: başlamamış / oynanıyor / devre arası. Ertelenen ve iptal
  -- edilen maçlar özeti bekletmez (ertelenen sonradan biterse özete eklenir).
  with wm as (
    select m.* from public.matches m
    left join public.groups g on g.id = m.group_id
    where m.season_id = p_season_id and m.week = p_week
      and m.deleted_at is null
      and g.region_id is not distinct from p_region_id
  )
  select count(*) filter (where status in ('notStarted', 'live', 'halftime')),
         jsonb_agg(public.match_result_data(id)
                   order by match_date nulls last, match_time nulls last, created_at)
           filter (where status = 'finished')
    into v_pending, v_items
    from wm;

  select id, auto_hidden, is_published into v_id, v_hidden, v_published
    from public.news
   where auto_kind = 'week_results' and season_id = p_season_id
     and region_id is not distinct from p_region_id and week = p_week;

  -- Tek maçlık haftada özet açılmaz (maç kartıyla aynı olurdu).
  if coalesce(v_pending, 0) > 0 or coalesce(jsonb_array_length(v_items), 0) < 2 then
    -- Hafta yeniden açıldı (ör. maç geri alındı): özet gizlenir.
    if v_id is not null and v_published then
      update public.news set is_published = false, auto_hidden = true
       where id = v_id;
    end if;
    return;
  end if;

  v_content := p_week || '. Hafta sonuçları' || E'\n\n' ||
    (select string_agg(public.result_text(x), E'\n\n' order by o)
       from jsonb_array_elements(v_items) with ordinality as a(x, o));

  if v_id is null then
    if not coalesce(v_enabled, true) then
      return;
    end if;
    insert into public.news (season_id, region_id, content, is_published,
                             auto_kind, week, auto_data)
    values (p_season_id, p_region_id, v_content, true, 'week_results', p_week,
            jsonb_build_object('week', p_week, 'matches', v_items));
  else
    update public.news
       set content = v_content,
           auto_data = jsonb_build_object('week', p_week, 'matches', v_items),
           is_published = case when auto_hidden then true else is_published end,
           auto_hidden = false
     where id = v_id;
  end if;
end;
$$;

-- 3e) Tek maç haberi + haftanın özeti
create or replace function public.refresh_result_news(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  m record;
  v_region uuid;
  v_enabled boolean;
  v_data jsonb;
  v_id uuid;
  v_published boolean;
begin
  select * into m from public.matches where id = p_match_id;
  if not found or m.season_id is null then
    return;
  end if;
  select g.region_id into v_region from public.groups g where g.id = m.group_id;
  select l.auto_result_news into v_enabled
    from public.seasons s join public.leagues l on l.id = s.league_id
   where s.id = m.season_id;

  select id, is_published into v_id, v_published
    from public.news
   where auto_kind = 'match_result' and match_id = p_match_id;

  if m.status = 'finished' and m.deleted_at is null then
    v_data := public.match_result_data(p_match_id);
    if v_id is null then
      if coalesce(v_enabled, true) then
        insert into public.news (season_id, region_id, content, is_published,
                                 auto_kind, match_id, week, auto_data)
        values (m.season_id, v_region, public.result_text(v_data), true,
                'match_result', p_match_id, m.week, v_data);
      end if;
    else
      update public.news
         set content = public.result_text(v_data),
             auto_data = v_data,
             week = m.week,
             region_id = v_region,
             is_published = case when auto_hidden then true else is_published end,
             auto_hidden = false
       where id = v_id;
    end if;
  elsif v_id is not null and v_published then
    update public.news set is_published = false, auto_hidden = true
     where id = v_id;
  end if;

  perform public.refresh_week_results_news(m.season_id, v_region, m.week);
end;
$$;

revoke all on function public.match_result_data(uuid) from public, anon, authenticated;
revoke all on function public.refresh_week_results_news(uuid, uuid, integer) from public, anon, authenticated;
revoke all on function public.refresh_result_news(uuid) from public, anon, authenticated;

-- 4a) matches tetikleyicisi
create or replace function public.matches_result_news()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_old_region uuid;
begin
  if new.status is distinct from old.status
     or new.deleted_at is distinct from old.deleted_at
     or new.week is distinct from old.week
     or new.group_id is distinct from old.group_id
     or (new.status = 'finished'
         and (new.home_score is distinct from old.home_score
              or new.away_score is distinct from old.away_score
              or new.home_team_id is distinct from old.home_team_id
              or new.away_team_id is distinct from old.away_team_id)) then
    -- Haber hatası maç kaydını asla engellemez.
    begin
      perform public.refresh_result_news(new.id);
      -- Hafta/grup değiştiyse eski haftanın özeti de yenilenir.
      if old.week is distinct from new.week or old.group_id is distinct from new.group_id then
        select region_id into v_old_region from public.groups where id = old.group_id;
        perform public.refresh_week_results_news(old.season_id, v_old_region, old.week);
      end if;
    exception when others then
      raise warning 'result news: %', sqlerrm;
    end;
  end if;
  return null;
end;
$$;

drop trigger if exists matches_result_news on public.matches;
create trigger matches_result_news
  after update on public.matches
  for each row execute function public.matches_result_news();

-- 4b) match_events tetikleyicisi: bitmiş maçta gol eklenir/değişir/silinirse
create or replace function public.match_events_result_news()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_match uuid := coalesce(new.match_id, old.match_id);
begin
  if (tg_op <> 'DELETE' and new.event_type = 'goal')
     or (tg_op <> 'INSERT' and old.event_type = 'goal') then
    if exists (select 1 from public.matches
                where id = v_match and status = 'finished') then
      begin
        perform public.refresh_result_news(v_match);
      exception when others then
        raise warning 'result news: %', sqlerrm;
      end;
    end if;
  end if;
  return null;
end;
$$;

drop trigger if exists match_events_result_news on public.match_events;
create trigger match_events_result_news
  after insert or update or delete on public.match_events
  for each row execute function public.match_events_result_news();

-- 5) Otomatik haberler bildirim göndermez (maç sonu bildirimi zaten var).
create or replace function public.news_push_notify()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_ids uuid[];
  v_league uuid;
  v_name text;
begin
  if new.auto_kind is not null then
    return new;
  end if;
  if not coalesce(new.is_published, false) then
    return new;
  end if;
  if tg_op = 'UPDATE' and coalesce(old.is_published, false) then
    return new;
  end if;
  select s.league_id, l.name into v_league, v_name
    from public.seasons s join public.leagues l on l.id = s.league_id
   where s.id = new.season_id;
  if v_league is null then
    return new;
  end if;

  with members as (
    select p.auth_uid as uid, g.region_id
    from public.season_team_players stp
    join public.players p on p.id = stp.player_id
    left join public.season_teams st
      on st.season_id = stp.season_id and st.team_id = stp.team_id
    left join public.groups g on g.id = st.group_id
    where stp.season_id = new.season_id and stp.is_active
    union
    select tm.user_id, g.region_id
    from public.team_managers tm
    left join public.season_teams st
      on st.season_id = tm.season_id and st.team_id = tm.team_id
    left join public.groups g on g.id = st.group_id
    where tm.season_id = new.season_id
  ),
  ids as (
    select mb.uid from members mb
    left join public.notification_prefs np on np.user_id = mb.uid
    where new.region_id is null
       or mb.region_id = new.region_id
       or coalesce(np.k_news, 'region') = 'league'
    union
    select o.user_id from public.league_owners o where o.league_id = v_league
    union
    select ro.user_id from public.region_owners ro
    join public.season_regions r on r.id = ro.region_id
    where r.season_id = new.season_id
      and (new.region_id is null or r.id = new.region_id)
    union
    select f.user_id from public.league_followers f where f.league_id = v_league
    union
    select fl.user_id from public.followed_leagues fl where fl.league_id = v_league
    union
    select ft.user_id from public.followed_teams ft where ft.league_id = v_league
  )
  select array_agg(distinct uid) into v_ids from ids where uid is not null;

  perform public.push_send(
    v_ids,
    coalesce(v_name, 'Turnuva') || ' · Yeni haber',
    left(regexp_replace(coalesce(new.content, ''), '\s+', ' ', 'g'), 120),
    '/',
    'news-' || new.id
  );
  return new;
end;
$function$;
