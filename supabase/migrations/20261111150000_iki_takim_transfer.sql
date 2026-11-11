-- Transfer döneminde aynı kişi aynı sezonda iki takımın kadrosunda olabilir.
-- Varsayılan davranış değişmez: aktif ikinci takım satırı, anahtar kapalıyken
-- (multi_team_roster_enabled) ya da transfer/kadro dönemi dışında reddedilir.
insert into public.app_settings (key, value)
values ('multi_team_roster_enabled', 'false'::jsonb)
on conflict (key) do nothing;

create or replace function public.guard_roster_multi_team()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(new.is_active, true) and exists (
    select 1 from public.season_team_players o
    where o.player_id = new.player_id and o.season_id = new.season_id
      and o.team_id <> new.team_id and coalesce(o.is_active, true)
      and o.id is distinct from new.id
  ) then
    if not (
      coalesce((select (value)::text = 'true' from public.app_settings
                where key = 'multi_team_roster_enabled'), false)
      and public.roster_add_open(new.season_id)
    ) then
      raise exception 'Oyuncu bu sezonda başka bir takımın kadrosunda.'
        using errcode = '23505',
              constraint = 'league_team_players_player_id_league_id_key';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists guard_roster_multi_team on public.season_team_players;
create trigger guard_roster_multi_team
  before insert or update on public.season_team_players
  for each row execute function public.guard_roster_multi_team();

alter table public.season_team_players
  drop constraint if exists league_team_players_player_id_league_id_key;
