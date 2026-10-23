-- Takım / Lisans Yönetimi filtreleri: etkin sezonlarda (turnuvası pasif
-- olmayan, silinmemiş) hangi oyuncu ve takım hangi turnuva/sezonda.
-- Tek jsonb döner (satır sınırına takılmaz). Yalnız kimlikler ve adlar.
create or replace function public.panel_memberships()
returns jsonb
language sql
stable
security definer
set search_path to ''
as $function$
  with act as (
    select s.id as season_id, s.name as season_name, l.id as league_id,
           l.name as league_name
      from public.seasons s
      join public.leagues l on l.id = s.league_id
     where s.deleted_at is null
       and coalesce(l.status, '') <> 'passive'
       and l.is_active is not false
  )
  select jsonb_build_object(
    'leagues', coalesce((select jsonb_object_agg(league_id, league_name)
                           from (select distinct league_id, league_name from act) x), '{}'::jsonb),
    'seasons', coalesce((select jsonb_object_agg(season_id,
                           jsonb_build_object('name', season_name, 'league', league_id))
                           from act), '{}'::jsonb),
    'teams', coalesce((select jsonb_object_agg(team_id, seasons) from (
                select st.team_id, jsonb_agg(distinct st.season_id) as seasons
                  from public.season_teams st join act on act.season_id = st.season_id
                 group by st.team_id) t), '{}'::jsonb),
    'players', coalesce((select jsonb_object_agg(player_id, seasons) from (
                select stp.player_id, jsonb_agg(distinct stp.season_id) as seasons
                  from public.season_team_players stp join act on act.season_id = stp.season_id
                 where stp.player_id is not null
                 group by stp.player_id) p), '{}'::jsonb))
$function$;
revoke all on function public.panel_memberships() from public, anon;
grant execute on function public.panel_memberships() to authenticated;
