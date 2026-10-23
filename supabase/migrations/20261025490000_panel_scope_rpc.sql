-- Yönetim paneli listeleri (Takım Yönetimi, Lisans Yönetimi) için kapsam.
-- Dizi olarak döner (satır sınırına takılmaz).

-- Sezon etkin mi: silinmemiş ve turnuvası pasif değil.
create or replace function public.season_is_active(p_season_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1 from public.seasons s
      join public.leagues l on l.id = s.league_id
     where s.id = p_season_id
       and s.deleted_at is null
       and coalesce(l.status, '') <> 'passive'
       and l.is_active is not false)
$function$;

-- Yalnız pasif / silinmiş turnuvalarda yer alan takım ve oyuncular.
create or replace function public.panel_hidden_ids()
returns jsonb
language sql
stable
security definer
set search_path to ''
as $function$
  select jsonb_build_object(
    'teams', coalesce((
      select jsonb_agg(team_id) from (
        select team_id from public.season_teams
         group by team_id
        having not bool_or(public.season_is_active(season_id))) x), '[]'::jsonb),
    'players', coalesce((
      select jsonb_agg(player_id) from (
        select player_id from public.season_team_players
         where player_id is not null
         group by player_id
        having not bool_or(public.season_is_active(season_id))) y), '[]'::jsonb))
$function$;
revoke all on function public.panel_hidden_ids() from public, anon;
grant execute on function public.panel_hidden_ids() to authenticated;

-- Verilen takımların etkin sezon kadrolarındaki oyuncular.
create or replace function public.panel_players_of_teams(p_team_ids uuid[])
returns jsonb
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(jsonb_agg(distinct stp.player_id), '[]'::jsonb)
    from public.season_team_players stp
   where stp.team_id = any(p_team_ids)
     and stp.player_id is not null
     and public.season_is_active(stp.season_id)
$function$;
revoke all on function public.panel_players_of_teams(uuid[]) from public, anon;
grant execute on function public.panel_players_of_teams(uuid[]) to authenticated;
