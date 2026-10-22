-- Uzatma dakikası: 30+2' → minute 30, added_minute 2. Eski sürümler yalnız
-- minute'ü görür (30'); sıralama ve devre ayrımı bozulmaz.
alter table public.match_events
  add column if not exists added_minute smallint
    check (added_minute between 1 and 30);
alter table public.match_highlights
  add column if not exists added_minute smallint
    check (added_minute between 1 and 30);

-- Dakika etiketi: 30+2' ya da 37'.
create or replace function public.minute_label(p_minute int, p_added int)
returns text
language sql
immutable
set search_path to ''
as $function$
  select case when p_minute is null then null
              when p_added is not null then p_minute || '+' || p_added || ''''
              else p_minute || '''' end
$function$;

-- Gol bildirimi: uzatmada 30+2'.
create or replace function public.match_events_goal_push()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_m record;
  v_home int;
  v_away int;
  v_scorer text;
  v_assist text;
  v_body text;
begin
  if new.event_type <> 'goal' then
    return new;
  end if;
  select id, status, home_team_id, away_team_id into v_m
    from public.matches where id = new.match_id;
  if v_m.id is null or v_m.status not in ('live', 'halftime') then
    return new;
  end if;

  select
    count(*) filter (where (e.team_id = v_m.home_team_id and not coalesce(e.is_own_goal, false))
                        or (e.team_id = v_m.away_team_id and coalesce(e.is_own_goal, false))),
    count(*) filter (where (e.team_id = v_m.away_team_id and not coalesce(e.is_own_goal, false))
                        or (e.team_id = v_m.home_team_id and coalesce(e.is_own_goal, false)))
    into v_home, v_away
    from public.match_events e
   where e.match_id = new.match_id and e.event_type = 'goal';

  select trim(coalesce(name, '') || ' ' || coalesce(surname, '')) into v_scorer
    from public.players where id = new.player_id;
  select trim(coalesce(name, '') || ' ' || coalesce(surname, '')) into v_assist
    from public.players where id = new.assist_player_id;

  v_body := public.match_score_text(new.match_id, v_home, v_away)
    || ' · '
    || coalesce(public.minute_label(new.minute, new.added_minute) || ' ', '')
    || coalesce(nullif(v_scorer, ''), 'Gol')
    || case when coalesce(new.is_own_goal, false) then ' (K.K.)'
            when coalesce(new.is_penalty, false) then ' (P)' else '' end
    || case when nullif(v_assist, '') is not null
            then ' (Asist: ' || v_assist || ')' else '' end;

  perform public.push_send(
    public.match_audience(new.match_id, false),
    'GOL!',
    v_body,
    '/',
    'goal-' || new.match_id
  );
  return new;
end;
$function$;

-- Sonuç verisi: 'minutes' (sayı, eski sürümler) yanında 'labels' (30+2').
create or replace function public.match_result_data(p_match_id uuid)
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
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
      e.added_minute,
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
           coalesce(jsonb_agg(minute order by minute, added_minute nulls first)
                    filter (where minute is not null), '[]'::jsonb) as minutes,
           coalesce(jsonb_agg(public.minute_label(minute, added_minute)
                              order by minute, added_minute nulls first)
                    filter (where minute is not null), '[]'::jsonb) as labels,
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
                  'name', name, 'n', n, 'pen', pen, 'og', og, 'minutes', minutes,
                  'labels', labels)
                  order by first_min, first_at)
                from s where side = 'home'), '[]'::jsonb),
      'away', coalesce((select jsonb_agg(jsonb_build_object(
                  'name', name, 'n', n, 'pen', pen, 'og', og, 'minutes', minutes,
                  'labels', labels)
                  order by first_min, first_at)
                from s where side = 'away'), '[]'::jsonb)
    )
  )
  from m
  left join t th on th.id = m.home_team_id
  left join t ta on ta.id = m.away_team_id
$function$;
