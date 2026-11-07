-- Arama: demo ve gizli turnuvaların futbolcuları yalnız turnuvayı
-- görebilene (admin, sahibi, kodla takip eden...) çıkar; demo turnuva adı
-- kilitli satır olarak da gösterilmez. Önceden tüm futbolcular aranıyordu.
CREATE OR REPLACE FUNCTION public.search_entities(p_q text, p_league uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with q as (
    select public._id_fold(trim(coalesce(p_q, ''))) as k
  ),
  seasons as (
    select s.id, s.league_id, l.name as league_name, s.created_at
    from public.seasons s
    join public.leagues l on l.id = s.league_id
    where s.deleted_at is null
      and public.can_view_league(l.id)
  ),
  league_hits as (
    select l.id, l.name, l.logo_url,
      not public.can_view_league(l.id) as locked,
      position(q.k in public._id_fold(l.name)) = 1 as starts
    from public.leagues l
    join q on length(q.k) >= 2
    where (public.can_view_league(l.id)
        or (coalesce(l.status, '') <> 'passive' and l.is_active is not false
            and not coalesce(l.is_demo, false)))
      and (public._id_fold(l.name) like '%' || q.k || '%'
        or public._id_fold(coalesce(l.short_name, '')) like '%' || q.k || '%')
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
  player_match as (
    select p.id, p.name, p.surname, p.photo_url,
      position(q.k in public._id_fold(p.name || ' ' || coalesce(p.surname, ''))) = 1
        or position(q.k in public._id_fold(coalesce(p.surname, ''))) = 1 as starts
    from public.players p
    join q on length(q.k) >= 2
    where public._id_fold(p.name || ' ' || coalesce(p.surname, '')) like '%' || q.k || '%'
      -- Yalnız görülebilen turnuvanın kadrosundaki futbolcu (demo / gizli
      -- turnuva oyuncusu misafire ve futbolcuya çıkmaz); admin hepsini görür.
      and (public.is_admin() or exists (
        select 1 from public.season_team_players stp
        join seasons se on se.id = stp.season_id
        where stp.player_id = p.id
      ))
    order by 5 desc, p.name, p.surname
    limit 40
  ),
  player_hits as (
    select pm.*, r.jersey_number, r.team_id, r.team_name, r.season_id,
      r.league_name
    from player_match pm
    left join lateral (
      select stp.jersey_number, t.id as team_id, t.name as team_name,
        stp.season_id, se.league_name
      from public.season_team_players stp
      join public.teams t on t.id = stp.team_id
      join seasons se on se.id = stp.season_id
      where stp.player_id = pm.id and stp.is_active
      order by se.created_at desc
      limit 1
    ) r on true
  )
  select jsonb_build_object(
    'leagues', coalesce((
      select jsonb_agg(to_jsonb(x) - 'starts' order by x.starts desc, x.name)
      from (select * from league_hits order by starts desc, name limit 10) x
    ), '[]'::jsonb),
    'teams', coalesce((
      select jsonb_agg(to_jsonb(x) - 'starts' order by x.starts desc, x.name)
      from (select * from team_hits order by starts desc, name limit 20) x
    ), '[]'::jsonb),
    'players', coalesce((
      select jsonb_agg(to_jsonb(x) - 'starts' order by x.starts desc, x.name, x.surname)
      from player_hits x
    ), '[]'::jsonb)
  )
$function$;
