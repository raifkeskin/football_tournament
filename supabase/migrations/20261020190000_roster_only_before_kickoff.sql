-- Esame: takım sorumlusu yalnız başlamamış (veya ertelenmiş) maçta girer /
-- düzenler; maç başladıktan sonra (canlı, devre arası, bitti) kapanır.
-- Admin, turnuva sahibi / bölge sorumlusu ve gözlemci (can_manage_match)
-- için sınır yok.

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
      and m.status in ('notStarted', 'postponed')
      and (public.manages_team(m.season_id, p_team_id)
           or exists (select 1 from public.teams t
                      join public.players p on p.id = t.manager_id
                      where t.id = p_team_id and p.auth_uid = auth.uid()))
      and now() >= public.match_roster_open_at(m.id)
  )
$$;
