-- Esame (match_rosters) ve maç olaylarında (match_events) season_id boş
-- kalabiliyordu; profil istatistikleri sezona göre saydığı için bu kayıtlar
-- görünmüyordu. season_id her zaman maçın sezonundan alınır.

create or replace function public.set_season_from_match()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select m.season_id into new.season_id
  from public.matches m
  where m.id = new.match_id;
  return new;
end;
$$;

drop trigger if exists match_rosters_season on public.match_rosters;
create trigger match_rosters_season
  before insert or update of match_id, season_id on public.match_rosters
  for each row execute function public.set_season_from_match();

drop trigger if exists match_events_season on public.match_events;
create trigger match_events_season
  before insert or update of match_id, season_id on public.match_events
  for each row execute function public.set_season_from_match();

-- Mevcut boş/yanlış kayıtlar.
update public.match_rosters r set season_id = m.season_id
from public.matches m
where m.id = r.match_id and r.season_id is distinct from m.season_id;

update public.match_events e set season_id = m.season_id
from public.matches m
where m.id = e.match_id and e.season_id is distinct from m.season_id;
