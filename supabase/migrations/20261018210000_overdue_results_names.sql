-- Sonucu girilmemiş maçlar: turnuva süzgeci ve takım adları (ana sayfa
-- uyarısı tek istekte gösterir).
drop function if exists public.overdue_result_matches();

create or replace function public.overdue_result_matches(p_league_id uuid default null)
returns table (
  id uuid,
  league_id uuid,
  season_id uuid,
  home_team_id uuid,
  away_team_id uuid,
  home_name text,
  away_name text,
  match_date date,
  match_time text
)
language sql
stable security definer
set search_path to ''
as $$
  select m.id, coalesce(m.league_id, s.league_id), m.season_id,
         m.home_team_id, m.away_team_id, ht.name::text, at.name::text,
         m.match_date, m.match_time::text
  from public.matches m
  join public.seasons s on s.id = m.season_id and s.deleted_at is null
  left join public.groups g on g.id = m.group_id
  left join public.teams ht on ht.id = m.home_team_id
  left join public.teams at on at.id = m.away_team_id
  where auth.uid() is not null
    and m.deleted_at is null
    and (g.id is null or g.deleted_at is null)
    and (p_league_id is null or coalesce(m.league_id, s.league_id) = p_league_id)
    and m.status in ('notStarted', 'live', 'halftime')
    and m.match_date between current_date - 60 and current_date
    and m.match_time ~ '^\d{1,2}:\d{2}'
    and ((m.match_date + left(m.match_time, 5)::time)
           at time zone 'Europe/Istanbul') < now() - interval '2 hours'
    and (
      public.owns_league(coalesce(m.league_id, s.league_id))
      or (g.region_id is not null and exists (
        select 1 from public.region_owners ro
        where ro.region_id = g.region_id and ro.user_id = auth.uid()
      ))
    )
  order by m.match_date, m.match_time;
$$;

revoke all on function public.overdue_result_matches(uuid) from public, anon;
grant execute on function public.overdue_result_matches(uuid) to authenticated;
