-- Esame açılış süresi turnuva bazında: takım sorumlusu kadroyu maç saatinden
-- leagues.roster_open_hours saat önce girebilir (varsayılan 1). Admin, turnuva
-- sahibi ve maç gözlemcisi için süre sınırı yoktur (can_edit_match_roster
-- değişmedi; açılış anını bu fonksiyondan okur).

alter table public.leagues
  add column if not exists roster_open_hours integer not null default 1
    check (roster_open_hours between 0 and 168);

create or replace function public.match_roster_open_at(p_match_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path to ''
as $$
  select ((m.match_date + left(m.match_time, 5)::time)
          at time zone 'Europe/Istanbul')
         - make_interval(hours => coalesce(l.roster_open_hours, 1))
  from public.matches m
  left join public.leagues l on l.id = m.league_id
  where m.id = p_match_id
    and m.match_date is not null
    and coalesce(m.match_time, '') ~ '^\d{1,2}:\d{2}'
$$;
