-- Esame: takım sorumlusu kendi takımının kadrosunu maç saatinden 1 saat önce
-- girebilir (maç bitene kadar). Admin, turnuva sahibi ve maç gözlemcisi için
-- süre sınırı yoktur. Maç tarih/saati Türkiye saatiyle tutulur.

create or replace function public.match_roster_open_at(p_match_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path to ''
as $$
  select ((m.match_date + left(m.match_time, 5)::time)
          at time zone 'Europe/Istanbul') - interval '1 hour'
  from public.matches m
  where m.id = p_match_id
    and m.match_date is not null
    and coalesce(m.match_time, '') ~ '^\d{1,2}:\d{2}'
$$;

create or replace function public.can_edit_match_roster(
  p_match_id uuid,
  p_team_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.can_manage_match(p_match_id) or exists (
    select 1 from public.matches m
    where m.id = p_match_id
      and p_team_id in (m.home_team_id, m.away_team_id)
      and m.status <> 'finished'
      and (public.manages_team(m.season_id, p_team_id)
           or exists (select 1 from public.teams t
                      where t.id = p_team_id and t.manager_id = auth.uid()))
      and now() >= public.match_roster_open_at(m.id)
  )
$$;

grant execute on function public.match_roster_open_at(uuid) to anon, authenticated;
grant execute on function public.can_edit_match_roster(uuid, uuid) to authenticated;

drop policy if exists match_rosters_write on public.match_rosters;
create policy match_rosters_write on public.match_rosters
  for all to authenticated
  using (public.owns_league(league_id)
         or public.can_edit_match_roster(match_id, team_id))
  with check (public.owns_league(league_id)
              or public.can_edit_match_roster(match_id, team_id));
