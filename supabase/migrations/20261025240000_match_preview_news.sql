-- ============================================================================
-- Maç günü haberi (maç sonucu haberinin "maç öncesi" eşi)
--
-- 1) leagues.auto_preview_news : turnuva bazında aç/kapa (yalnız admin)
-- 2) news.auto_kind:
--      match_preview : maç günü sabah 09:00'da tek maçın kartı (A)
--                      (gece yarısından sonraki erken maçta en geç 3 saat önce)
--      day_preview   : o gün bölgede 2+ maç varsa günün programı (C)
-- 3) Maç bitince (sonuç haberi gelir), ertelenince ya da iptal olunca kart
--    gizlenir; günün tüm maçları bitince program da gizlenir.
-- 4) Kart verisi: takımlar, puan (+ eşit puan yoksa sıra), son 5 maç, iki
--    takımın son maçı, saha, hava durumu. Gözlemci bilgisi yok.
-- 5) Zamanlayıcı her 15 dakikada oluşturur/günceller (hava durumu, puan);
--    matches tetikleyicisi saat/saha/durum değişikliğini hemen yansıtır.
-- 6) Bildirim göndermez (news_push_notify otomatik haberleri atlar).
-- ============================================================================

-- 1) Turnuva ayarı
alter table public.leagues
  add column if not exists auto_preview_news boolean not null default true;

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
    if new.auto_preview_news is distinct from old.auto_preview_news then
      raise exception 'Maç günü haberi ayarını yalnızca admin değiştirebilir.'
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

-- 2) Haber türleri
alter table public.news drop constraint if exists news_auto_kind_check;
alter table public.news add constraint news_auto_kind_check
  check (auto_kind in ('match_result', 'week_results', 'instagram',
                       'match_preview', 'day_preview'));

create unique index if not exists news_auto_preview_uq
  on public.news (match_id) where auto_kind = 'match_preview';
create unique index if not exists news_auto_day_uq
  on public.news (season_id,
                  coalesce(region_id, '00000000-0000-0000-0000-000000000000'::uuid),
                  (auto_data->>'date'))
  where auto_kind = 'day_preview';

-- 3a) Maçın başlama anı (İstanbul saati). Saat yoksa öğlen sayılır.
create or replace function public.match_kickoff_ts(p_date date, p_time text)
returns timestamptz
language sql
immutable
set search_path to ''
as $$
  select case when p_date is null then null else
    (p_date + case when coalesce(p_time, '') ~ '^\d{1,2}:\d{2}'
                   then substring(p_time from '^\d{1,2}:\d{2}')::time
                   else time '12:00' end)
    at time zone 'Europe/Istanbul' end
$$;

-- Kart bu andan itibaren görünür: maç günü 09:00, erken maçta en geç 3 saat önce.
create or replace function public.match_preview_due_at(p_date date, p_time text)
returns timestamptz
language sql
immutable
set search_path to ''
as $$
  select least((p_date + time '09:00') at time zone 'Europe/Istanbul',
               public.match_kickoff_ts(p_date, p_time) - interval '3 hours')
$$;

-- 3b) Takımın sezondaki durumu: puan, oynanan, sıra (eşit puanlı takım
-- yoksa), son 5 maç. Puan tablosundaki hesapla aynı: eleme maçları sayılmaz.
create or replace function public.preview_team_data(p_match_id uuid, p_team_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  with m as (select * from public.matches where id = p_match_id),
  played as (
    select x.*,
           case when x.home_team_id = p_team_id then x.home_score else x.away_score end as gf,
           case when x.home_team_id = p_team_id then x.away_score else x.home_score end as ga
    from public.matches x, m
    where x.season_id = m.season_id and x.deleted_at is null
      and x.status = 'finished' and x.id <> m.id
      and p_team_id in (x.home_team_id, x.away_team_id)
  ),
  form as (
    select coalesce(jsonb_agg(r order by k), '[]'::jsonb) as f from (
      select case when coalesce(gf, 0) > coalesce(ga, 0) then 'G'
                  when coalesce(gf, 0) = coalesce(ga, 0) then 'B' else 'M' end as r,
             coalesce(match_date::text, '') || '|' || coalesce(match_time, '') || '|'
               || lpad(coalesce(week, 0)::text, 3, '0') as k
      from played
      order by match_date desc nulls last, match_time desc nulls last, week desc nulls last
      limit 5
    ) t
  ),
  grp as (
    -- Grup puan tablosu (yalnız lig maçları, maç grubunda).
    select t.team_id, sum(t.pts)::int as pts, count(*)::int as n
    from (
      select x.home_team_id as team_id,
             case when x.home_score > x.away_score then 3
                  when x.home_score = x.away_score then 1 else 0 end as pts
      from public.matches x, m
      where m.group_id is not null and x.group_id = m.group_id
        and x.season_id = m.season_id and x.deleted_at is null
        and x.status = 'finished' and x.tiebreak is null
      union all
      select x.away_team_id,
             case when x.away_score > x.home_score then 3
                  when x.away_score = x.home_score then 1 else 0 end
      from public.matches x, m
      where m.group_id is not null and x.group_id = m.group_id
        and x.season_id = m.season_id and x.deleted_at is null
        and x.status = 'finished' and x.tiebreak is null
    ) t
    group by t.team_id
  ),
  me as (select pts, n from grp where team_id = p_team_id)
  select jsonb_build_object(
    'id', tm.id, 'name', tm.name, 'logo', tm.logo_url, 'color', tm.first_color,
    'points', (select pts from me),
    'played', (select n from me),
    'rank', case
      when (select n from me) is null or (select tiebreak from m) is not null then null
      when exists (select 1 from grp g where g.team_id <> p_team_id
                    and g.pts = (select pts from me)) then null
      else 1 + (select count(*) from grp g where g.pts > (select pts from me))
    end,
    'form', (select f from form)
  )
  from public.teams tm where tm.id = p_team_id
$$;

-- 3c) Tek maçın kart verisi
create or replace function public.match_preview_data(p_match_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  with m as (select * from public.matches where id = p_match_id),
  h2h as (
    select x.match_date, x.home_team_id, x.home_score, x.away_score
    from public.matches x, m
    where x.deleted_at is null and x.status = 'finished' and x.id <> m.id
      and ((x.home_team_id = m.home_team_id and x.away_team_id = m.away_team_id)
        or (x.home_team_id = m.away_team_id and x.away_team_id = m.home_team_id))
    order by x.match_date desc nulls last, x.match_time desc nulls last
    limit 1
  )
  select jsonb_build_object(
    'match_id', m.id,
    'week', m.week,
    'date', m.match_date,
    'time', m.match_time,
    'status', m.status,
    'cup', nullif(concat_ws(' · ', nullif(m.cup_name, ''), nullif(m.cup_round, '')), ''),
    'home', public.preview_team_data(m.id, m.home_team_id),
    'away', public.preview_team_data(m.id, m.away_team_id),
    'pitch', p.name,
    'weather', case when w.match_id is not null then jsonb_build_object(
                 'temp', round(w.temp), 'code', w.code, 'desc', w.description,
                 'wind', round(w.wind_kmh), 'pop', w.pop, 'day', w.is_day) end,
    'h2h', (select jsonb_build_object(
              'year', extract(year from h.match_date)::int,
              'home_id', h.home_team_id,
              'hs', h.home_score, 'as', h.away_score)
            from h2h h)
  )
  from m
  left join public.pitches p on p.id = m.pitch_id
  left join public.match_weather w on w.match_id = m.id
$$;

-- 3d) Eski sürümlerin düz metin olarak göstereceği içerik
create or replace function public.preview_text(p jsonb)
returns text
language sql
immutable
set search_path to ''
as $$
  select concat_ws(E'\n',
    'Maç günü: ' || (p->'home'->>'name') || ' – ' || (p->'away'->>'name'),
    concat_ws(' · ', nullif(p->>'time', ''), nullif(p->>'pitch', '')))
$$;

-- 3e) Günün programı: (sezon, bölge, gün) içinde 2+ maç varsa
create or replace function public.refresh_day_preview_news(
  p_season_id uuid, p_region_id uuid, p_date date)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_enabled boolean;
  v_items jsonb;
  v_pending int;
  v_due timestamptz;
  v_last timestamptz;
  v_week int;
  v_data jsonb;
  v_content text;
  v_id uuid;
  v_published boolean;
begin
  if p_season_id is null or p_date is null then
    return;
  end if;
  select l.auto_preview_news into v_enabled
    from public.seasons s join public.leagues l on l.id = s.league_id
   where s.id = p_season_id;

  with dm as (
    select m.* from public.matches m
    left join public.groups g on g.id = m.group_id
    where m.season_id = p_season_id and m.match_date = p_date
      and m.deleted_at is null
      and m.status not in ('postponed', 'cancelled')
      and m.home_team_id is not null and m.away_team_id is not null
      and g.region_id is not distinct from p_region_id
  )
  select jsonb_agg(jsonb_build_object(
           'match_id', id, 'time', match_time, 'status', status,
           'home', (select jsonb_build_object('id', t.id, 'name', t.name,
                      'logo', t.logo_url, 'color', t.first_color)
                    from public.teams t where t.id = home_team_id),
           'away', (select jsonb_build_object('id', t.id, 'name', t.name,
                      'logo', t.logo_url, 'color', t.first_color)
                    from public.teams t where t.id = away_team_id),
           'pitch', (select p.name from public.pitches p where p.id = pitch_id))
           order by public.match_kickoff_ts(match_date, match_time), created_at),
         count(*) filter (where status in ('notStarted', 'live', 'halftime')),
         min(public.match_preview_due_at(match_date, match_time)),
         max(public.match_kickoff_ts(match_date, match_time)),
         min(week)
    into v_items, v_pending, v_due, v_last, v_week
    from dm;

  select id, is_published into v_id, v_published
    from public.news
   where auto_kind = 'day_preview' and season_id = p_season_id
     and region_id is not distinct from p_region_id
     and auto_data->>'date' = p_date::text;

  if coalesce(jsonb_array_length(v_items), 0) < 2 or coalesce(v_pending, 0) = 0
     or now() < v_due or now() > v_last + interval '6 hours' then
    if v_id is not null and v_published then
      update public.news set is_published = false, auto_hidden = true
       where id = v_id;
    end if;
    return;
  end if;

  v_data := jsonb_build_object('date', p_date::text, 'week', v_week, 'matches', v_items);
  v_content := 'Bugünün maçları' || E'\n\n' ||
    (select string_agg(concat_ws(' · ', nullif(x->>'time', ''),
                         (x->'home'->>'name') || ' – ' || (x->'away'->>'name'),
                         nullif(x->>'pitch', '')), E'\n' order by o)
       from jsonb_array_elements(v_items) with ordinality as a(x, o));

  if v_id is null then
    if not coalesce(v_enabled, true) then
      return;
    end if;
    insert into public.news (season_id, region_id, content, is_published,
                             auto_kind, week, auto_data)
    values (p_season_id, p_region_id, v_content, true, 'day_preview', v_week, v_data);
  else
    update public.news
       set content = v_content,
           auto_data = v_data,
           week = v_week,
           is_published = case when auto_hidden then true else is_published end,
           auto_hidden = false
     where id = v_id
       and (auto_data is distinct from v_data or auto_hidden);
  end if;
end;
$$;

-- 3f) Tek maçın kartı + günün programı
create or replace function public.refresh_preview_news(p_match_id uuid)
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
  v_kick timestamptz;
begin
  select * into m from public.matches where id = p_match_id;
  if not found or m.season_id is null then
    return;
  end if;
  select g.region_id into v_region from public.groups g where g.id = m.group_id;
  select l.auto_preview_news into v_enabled
    from public.seasons s join public.leagues l on l.id = s.league_id
   where s.id = m.season_id;

  select id, is_published into v_id, v_published
    from public.news
   where auto_kind = 'match_preview' and match_id = p_match_id;

  v_kick := public.match_kickoff_ts(m.match_date, m.match_time);

  if m.deleted_at is null
     and m.status in ('notStarted', 'live', 'halftime')
     and m.home_team_id is not null and m.away_team_id is not null
     and v_kick is not null
     and now() >= public.match_preview_due_at(m.match_date, m.match_time)
     and now() <= v_kick + interval '6 hours' then
    v_data := public.match_preview_data(p_match_id);
    if v_id is null then
      if coalesce(v_enabled, true) then
        insert into public.news (season_id, region_id, content, is_published,
                                 auto_kind, match_id, week, auto_data)
        values (m.season_id, v_region, public.preview_text(v_data), true,
                'match_preview', p_match_id, m.week, v_data);
      end if;
    else
      update public.news
         set content = public.preview_text(v_data),
             auto_data = v_data,
             week = m.week,
             region_id = v_region,
             is_published = case when auto_hidden then true else is_published end,
             auto_hidden = false
       where id = v_id
         and (auto_data is distinct from v_data or auto_hidden
              or region_id is distinct from v_region);
    end if;
  elsif v_id is not null and v_published then
    update public.news set is_published = false, auto_hidden = true
     where id = v_id;
  end if;

  perform public.refresh_day_preview_news(m.season_id, v_region, m.match_date);
end;
$$;

-- 3g) Zamanlayıcı: dün/bugün/yarın maçları ve hâlâ açık kartlar
create or replace function public.preview_news_tick()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_today date := (now() at time zone 'Europe/Istanbul')::date;
  r record;
begin
  for r in
    select m.id from public.matches m
     where m.match_date between v_today - 1 and v_today + 1
       and m.deleted_at is null
    union
    select n.match_id from public.news n
     where n.auto_kind = 'match_preview' and n.is_published and n.match_id is not null
  loop
    begin
      perform public.refresh_preview_news(r.id);
    exception when others then
      raise warning 'preview news %: %', r.id, sqlerrm;
    end;
  end loop;

  -- Maçı silinmiş/taşınmış eski programlar
  update public.news set is_published = false, auto_hidden = true
   where auto_kind = 'day_preview' and is_published
     and (auto_data->>'date')::date < v_today - 1;
end;
$$;

revoke all on function public.preview_team_data(uuid, uuid) from public, anon, authenticated;
revoke all on function public.match_preview_data(uuid) from public, anon, authenticated;
revoke all on function public.refresh_day_preview_news(uuid, uuid, date) from public, anon, authenticated;
revoke all on function public.refresh_preview_news(uuid) from public, anon, authenticated;
revoke all on function public.preview_news_tick() from public, anon, authenticated;

-- 4) matches tetikleyicisi: saat, saha, durum, takım değişikliği hemen yansır
create or replace function public.matches_preview_news()
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
     or new.match_date is distinct from old.match_date
     or new.match_time is distinct from old.match_time
     or new.pitch_id is distinct from old.pitch_id
     or new.group_id is distinct from old.group_id
     or new.home_team_id is distinct from old.home_team_id
     or new.away_team_id is distinct from old.away_team_id then
    -- Haber hatası maç kaydını asla engellemez.
    begin
      perform public.refresh_preview_news(new.id);
      if old.match_date is distinct from new.match_date
         or old.group_id is distinct from new.group_id then
        select region_id into v_old_region from public.groups where id = old.group_id;
        perform public.refresh_day_preview_news(old.season_id, v_old_region, old.match_date);
      end if;
    exception when others then
      raise warning 'preview news: %', sqlerrm;
    end;
  end if;
  return null;
end;
$$;

drop trigger if exists matches_preview_news on public.matches;
create trigger matches_preview_news
  after update on public.matches
  for each row execute function public.matches_preview_news();

-- 5) Her 15 dakikada (hava durumu :07'de güncellenir)
select cron.unschedule('match-preview-news')
 where exists (select 1 from cron.job where jobname = 'match-preview-news');
select cron.schedule('match-preview-news', '*/15 * * * *',
                     'select public.preview_news_tick()');
