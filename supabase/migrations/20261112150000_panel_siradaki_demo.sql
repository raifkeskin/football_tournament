-- Yönetim Paneli: (1) demo turnuvalar da panelde görünür (demolar herkes gibi);
-- (2) "Sıradaki maçlar": her grubun (bölgenin) bugünden sonraki en yakın
-- haftasının oynanmamış maçları; hafta bitince sonraki hafta gelir.

create or replace function public.admin_panel_scope()
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  with lg as (
    select l.id, l.name,
           public.owns_league(l.id) as can_all
      from public.leagues l
     where coalesce(l.status, 'active') = 'active'
       and (public.owns_league(l.id) or exists (
             select 1 from public.region_owners ro
             join public.season_regions r on r.id = ro.region_id
             join public.seasons s on s.id = r.season_id
            where ro.user_id = auth.uid() and s.league_id = l.id
              and coalesce(s.is_active, true) and s.deleted_at is null))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'league_id', lg.id,
      'name', lg.name,
      'can_all', lg.can_all,
      'regions', coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name)
                         order by r.sort_order, r.name)
          from public.season_regions r
          join public.seasons s on s.id = r.season_id
         where s.league_id = lg.id and coalesce(s.is_active, true)
           and s.deleted_at is null
           and (lg.can_all or exists (
                 select 1 from public.region_owners ro
                  where ro.region_id = r.id and ro.user_id = auth.uid()))
      ), '[]'::jsonb)
    ) order by lg.name), '[]'::jsonb)
  from lg
  where auth.uid() is not null
$function$;

create or replace function public.admin_panel_upcoming(
  p_league_id uuid,
  p_region_id uuid default null
)
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  with today as (
    select (now() at time zone 'Europe/Istanbul')::date as d
  ),
  cand as (
    select m.id, m.status, m.match_date, m.match_time, m.week, m.group_id,
           m.home_team_id, m.away_team_id, m.pitch_id, m.referee_id,
           m.referee_name, g.region_id, r.name as region_name
      from public.matches m
      join public.seasons s on s.id = m.season_id
      left join public.groups g on g.id = m.group_id
      left join public.season_regions r on r.id = g.region_id
      cross join today t
     where m.league_id = p_league_id
       and m.deleted_at is null
       and coalesce(s.is_active, true) and s.deleted_at is null
       and m.status in ('notStarted', 'postponed')
       and (m.match_date is null or m.match_date > t.d)
       and (p_region_id is null or g.region_id = p_region_id)
       and (public.owns_league(m.league_id) or exists (
             select 1 from public.region_owners ro
              where ro.region_id = g.region_id and ro.user_id = auth.uid()))
  ),
  nxt as (
    select c.* from cand c
     where c.week is null
        or c.week = (select min(x.week) from cand x
                      where x.group_id is not distinct from c.group_id
                        and x.week is not null)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', n.id,
      'status', n.status,
      'date', n.match_date,
      'time', n.match_time,
      'week', n.week,
      'region', n.region_name,
      'home', h.name, 'home_logo', h.logo_url,
      'away', a.name, 'away_logo', a.logo_url,
      'home_color', h.first_color, 'away_color', a.first_color,
      'pitch', pt.name,
      'referee', coalesce(nullif(trim(n.referee_name), ''), (
        select trim(rf.name) from public.referees rf where rf.id = n.referee_id))
    ) order by n.match_date nulls last, n.match_time), '[]'::jsonb)
  from nxt n
  join public.teams h on h.id = n.home_team_id
  join public.teams a on a.id = n.away_team_id
  left join public.pitches pt on pt.id = n.pitch_id
  where auth.uid() is not null
$function$;

grant execute on function public.admin_panel_scope() to authenticated;
grant execute on function public.admin_panel_upcoming(uuid, uuid) to authenticated;
