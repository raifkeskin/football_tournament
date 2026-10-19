-- Ana sayfa katılım kutusu (akordiyon): her sorgu için takım kimliği ve
-- gelen / gelemeyen sayıları. Yalnız alan eklenir; eski derlemeler etkilenmez.
create or replace function public.attendance_my_polls(p_league_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', ap.id,
      'player_id', pl.id,
      'match_id', m.id,
      'team_id', ap.team_id,
      'team', t.name,
      'team_logo', t.logo_url,
      'home', h.name,
      'away', a.name,
      'date', m.match_date,
      'time', m.match_time,
      'pitch', pt.name,
      'status', ans.status,
      'yes_count', (select count(*) from public.attendance_answers x
                     where x.poll_id = ap.id and x.status = 'yes'),
      'no_count', (select count(*) from public.attendance_answers x
                    where x.poll_id = ap.id and x.status = 'no')
    ) order by m.match_date nulls last, m.match_time), '[]'::jsonb)
    from public.players pl
    join public.attendance_polls ap
      on public.attendance_in_roster(ap.season_id, ap.team_id, pl.id)
    join public.matches m on m.id = ap.match_id
    join public.teams t on t.id = ap.team_id
    join public.teams h on h.id = m.home_team_id
    join public.teams a on a.id = m.away_team_id
    left join public.pitches pt on pt.id = m.pitch_id
    left join public.attendance_answers ans on ans.poll_id = ap.id and ans.player_id = pl.id
   where auth.uid() is not null
     and pl.auth_uid = auth.uid()
     and ap.closed_at is null
     and public.attendance_match_open(ap.match_id)
     and (p_league_id is null or m.league_id = p_league_id);
$$;
