-- Ana sayfa uyarısı: oynanacak haftada (her grubun oynanmamış en küçük
-- haftası) tarihi ya da stadı girilmemiş maçlar. Yalnız maçı yönetenler
-- (admin, kurucu başkan, maçın bölge sorumlusu) görür (owns_match).
create or replace function public.unscheduled_matches(p_league_id uuid)
returns table (
  id uuid, home_name text, away_name text, week int,
  match_date date, match_time text, missing_date boolean, missing_pitch boolean
)
language sql
stable
security definer
set search_path to ''
as $function$
  with open_m as (
    select m.*
      from public.matches m
     where m.league_id = p_league_id
       and m.deleted_at is null
       and m.status = 'notStarted'
       and m.week is not null
       and not public.is_demo_league(m.league_id)
  ), next_week as (
    select coalesce(group_id::text, '') g, min(week) w from open_m group by 1
  )
  select m.id, th.name, ta.name, m.week, m.match_date::date, m.match_time::text,
         m.match_date is null, m.pitch_id is null
    from open_m m
    join next_week n on n.g = coalesce(m.group_id::text, '') and n.w = m.week
    left join public.teams th on th.id = m.home_team_id
    left join public.teams ta on ta.id = m.away_team_id
   where (m.match_date is null or m.pitch_id is null)
     and public.owns_match(m.id)
   order by m.week, m.match_date nulls first, m.match_time
$function$;
revoke all on function public.unscheduled_matches(uuid) from public;
grant execute on function public.unscheduled_matches(uuid) to authenticated;
