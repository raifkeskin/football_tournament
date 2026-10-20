-- Otomatik haber verisindeki takımlara kısa ad (teams.short_name) eklenir.
-- Ana sayfa haber kartı, adında çok uzun bir kelime olan takımda kısa adı
-- gösterir. Mevcut haberler de aşağıda güncellenir.

CREATE OR REPLACE FUNCTION public.match_result_data(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    select id, name, short_name, logo_url, first_color from public.teams
  )
  select jsonb_build_object(
    'match_id', m.id,
    'week', m.week,
    'date', m.match_date,
    'home', jsonb_build_object('id', m.home_team_id, 'name', th.name,
                               'short', th.short_name, 'logo', th.logo_url, 'color', th.first_color),
    'away', jsonb_build_object('id', m.away_team_id, 'name', ta.name,
                               'short', ta.short_name, 'logo', ta.logo_url, 'color', ta.first_color),
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
$function$

;

CREATE OR REPLACE FUNCTION public.preview_team_data(p_match_id uuid, p_team_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    'id', tm.id, 'name', tm.name, 'short', tm.short_name, 'logo', tm.logo_url, 'color', tm.first_color,
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
$function$

;

CREATE OR REPLACE FUNCTION public.refresh_day_preview_news(p_season_id uuid, p_region_id uuid, p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
                      'short', t.short_name, 'logo', t.logo_url, 'color', t.first_color)
                    from public.teams t where t.id = home_team_id),
           'away', (select jsonb_build_object('id', t.id, 'name', t.name,
                      'short', t.short_name, 'logo', t.logo_url, 'color', t.first_color)
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
$function$

;

-- Mevcut haberler: auto_data içindeki her takım nesnesine kısa ad.
create or replace function pg_temp.news_add_short(j jsonb) returns jsonb
language plpgsql as $$
declare
  k text; v jsonb; r jsonb; s text;
begin
  if jsonb_typeof(j) = 'array' then
    select coalesce(jsonb_agg(pg_temp.news_add_short(e)), '[]'::jsonb) into r
      from jsonb_array_elements(j) e;
    return r;
  elsif jsonb_typeof(j) = 'object' then
    r := '{}'::jsonb;
    for k, v in select * from jsonb_each(j) loop
      r := r || jsonb_build_object(k, pg_temp.news_add_short(v));
    end loop;
    if r ? 'id' and r ? 'logo' and r ? 'name' then
      select short_name into s from public.teams where id::text = r->>'id';
      r := r || jsonb_build_object('short', s);
    end if;
    return r;
  end if;
  return j;
end $$;

update public.news set auto_data = pg_temp.news_add_short(auto_data)
 where auto_data is not null;
