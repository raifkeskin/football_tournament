-- Sonuç haberinde maç süresini aşan gol dakikası, maç detayındaki gibi
-- uzatma yazılır: 35'lik devrelerde 71 → 70+1'. Uzatma ayrı girildiyse
-- (added_minute) olduğu gibi kalır.
CREATE OR REPLACE FUNCTION public.match_result_data(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with m as (
    select mm.*,
           2 * coalesce(se.match_period_duration, 30) as full_time
    from public.matches mm
    left join public.seasons se on se.id = mm.season_id
    where mm.id = p_match_id
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
      case when e.added_minute is null and e.minute > m.full_time
           then public.minute_label(m.full_time, e.minute - m.full_time)
           else public.minute_label(e.minute, e.added_minute)
      end as label,
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
           coalesce(jsonb_agg(label order by minute, added_minute nulls first)
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

revoke all on function public.match_result_data(uuid) from public, anon, authenticated;
