-- Ana sayfa araması: takım ve futbolcu (ad, takım, numara; telefon/TC yok).
-- Türkçe harfe duyarsız (_id_fold). Gizli turnuvalar ve silinen sezonlar
-- aranmaz. p_league verilirse yalnız o turnuva. Yeni özellik:
-- search_enabled kapalı (admin görür).

create or replace function public.search_entities(p_q text, p_league uuid default null)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $function$
  with q as (
    select public._id_fold(trim(coalesce(p_q, ''))) as k
  ),
  seasons as (
    select s.id, s.league_id, l.name as league_name, s.created_at
    from public.seasons s
    join public.leagues l on l.id = s.league_id
    where s.deleted_at is null
      and not coalesce(l.is_private, false)
      and (p_league is null or s.league_id = p_league)
  ),
  team_hits as (
    select distinct on (t.id)
      t.id, t.name, t.logo_url, st.season_id, se.league_id, se.league_name,
      position(q.k in public._id_fold(t.name)) = 1 as starts
    from public.teams t
    join public.season_teams st on st.team_id = t.id
    join seasons se on se.id = st.season_id
    join q on length(q.k) >= 2
    where public._id_fold(t.name) like '%' || q.k || '%'
    order by t.id, se.created_at desc
  ),
  player_hits as (
    select distinct on (p.id)
      p.id, p.name, p.surname, p.photo_url,
      stp.jersey_number, t.id as team_id, t.name as team_name,
      stp.season_id, se.league_name,
      position(q.k in public._id_fold(p.name || ' ' || coalesce(p.surname, ''))) = 1
        or position(q.k in public._id_fold(coalesce(p.surname, ''))) = 1 as starts
    from public.players p
    join public.season_team_players stp on stp.player_id = p.id and stp.is_active
    join public.teams t on t.id = stp.team_id
    join seasons se on se.id = stp.season_id
    join q on length(q.k) >= 2
    where public._id_fold(p.name || ' ' || coalesce(p.surname, '')) like '%' || q.k || '%'
    order by p.id, se.created_at desc
  )
  select jsonb_build_object(
    'teams', coalesce((
      select jsonb_agg(to_jsonb(x) - 'starts' order by x.starts desc, x.name)
      from (select * from team_hits order by starts desc, name limit 20) x
    ), '[]'::jsonb),
    'players', coalesce((
      select jsonb_agg(to_jsonb(x) - 'starts' order by x.starts desc, x.name, x.surname)
      from (select * from player_hits order by starts desc, name, surname limit 40) x
    ), '[]'::jsonb)
  )
$function$;

grant execute on function public.search_entities(text, uuid) to anon, authenticated;

insert into public.app_settings (key, value)
values ('search_enabled', 'false'::jsonb)
on conflict (key) do nothing;
