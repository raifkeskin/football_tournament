-- Yönetim Paneli (menü): admin, kurucu başkan ve bölge sorumlusu.
-- app_settings.admin_panel_enabled kapalıyken yalnız admin görür.

insert into public.app_settings (key, value)
values ('admin_panel_enabled', 'false'::jsonb)
on conflict (key) do nothing;

-- Kullanıcının yönettiği turnuvalar ve bölgeleri. can_all: tüm bölgeler
-- (admin / kurucu başkan); değilse yalnız sorumlu olduğu bölgeler.
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
       and not coalesce(l.is_demo, false)
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

-- Panel maçları: maç öncesi (bugünden 7 gün), canlı, maç sonu (son 3 gün).
create or replace function public.admin_panel_matches(
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
  ms as (
    select m.*, g.region_id, r.name as region_name,
           s.starting_player_count as need_xi
      from public.matches m
      join public.seasons s on s.id = m.season_id
      left join public.groups g on g.id = m.group_id
      left join public.season_regions r on r.id = g.region_id
      cross join today t
     where m.league_id = p_league_id
       and m.deleted_at is null
       and coalesce(s.is_active, true) and s.deleted_at is null
       and (p_region_id is null or g.region_id = p_region_id)
       and (public.owns_league(m.league_id) or exists (
             select 1 from public.region_owners ro
              where ro.region_id = g.region_id and ro.user_id = auth.uid()))
       and (
         m.status in ('live', 'halftime')
         or (m.status in ('notStarted', 'postponed')
             and m.match_date between t.d and t.d + 6)
         or (m.status = 'finished' and m.match_date between t.d - 3 and t.d)
       )
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', ms.id,
      'status', ms.status,
      'date', ms.match_date,
      'time', ms.match_time,
      'week', ms.week,
      'region', ms.region_name,
      'home_id', ms.home_team_id,
      'away_id', ms.away_team_id,
      'home', h.name, 'home_logo', h.logo_url,
      'away', a.name, 'away_logo', a.logo_url,
      'home_color', h.first_color, 'away_color', a.first_color,
      'home_score', ms.home_score,
      'away_score', ms.away_score,
      'kickoff_at', ms.kickoff_at,
      'pitch', pt.name,
      'youtube_url', coalesce(nullif(trim(ms.youtube_url), ''), (
        select mm.url from public.match_media mm
         where mm.match_id = ms.id and mm.media_type = 'Maç Yayın Linki'
         order by mm.created_at desc limit 1)),
      'referee', coalesce(nullif(trim(ms.referee_name), ''), (
        select trim(rf.name) from public.referees rf where rf.id = ms.referee_id)),
      'need_xi', coalesce(ms.need_xi, 11),
      'xi_home', (select count(*) from public.match_rosters x
                   where x.match_id = ms.id and x.team_id = ms.home_team_id
                     and x.is_starting),
      'xi_away', (select count(*) from public.match_rosters x
                   where x.match_id = ms.id and x.team_id = ms.away_team_id
                     and x.is_starting),
      'controller', (
        select coalesce(nullif(trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, '')), ''), 'Bir yönetici')
          from public.match_control c
          left join public.players p on p.auth_uid = c.user_id
         where c.match_id = ms.id limit 1),
      'controller_me', exists (select 1 from public.match_control c
                                where c.match_id = ms.id and c.user_id = auth.uid()),
      'photo_home', exists (select 1 from public.match_media mm
                             where mm.match_id = ms.id and mm.team_id = ms.home_team_id
                               and mm.media_type = 'Takım Fotosu'),
      'photo_away', exists (select 1 from public.match_media mm
                             where mm.match_id = ms.id and mm.team_id = ms.away_team_id
                               and mm.media_type = 'Takım Fotosu'),
      'moments', (select count(*) from public.match_media mm
                   where mm.match_id = ms.id and mm.media_type = 'Önemli An'),
      'videos', (select count(*) from public.videos v where v.match_id = ms.id),
      'preview_news', exists (select 1 from public.news n
                               where n.match_id = ms.id and n.auto_kind = 'match_preview'
                                 and n.is_published),
      'result_news', (select case when bool_or(n.is_published) then 'published'
                                  else 'pending' end
                        from public.news n
                       where n.match_id = ms.id and n.auto_kind = 'match_result'),
      'motm', exists (select 1 from public.match_events e
                       where e.match_id = ms.id and e.event_type = 'man_of_the_match'),
      'clips', (select count(*) from public.match_highlights hl
                 where hl.match_id = ms.id and hl.status = 'approved'),
      'clip_status', public.highlights_auto_status_v2(ms.id)
    ) order by ms.match_date, ms.match_time), '[]'::jsonb)
  from ms
  join public.teams h on h.id = ms.home_team_id
  join public.teams a on a.id = ms.away_team_id
  left join public.pitches pt on pt.id = ms.pitch_id
  where auth.uid() is not null
$function$;

grant execute on function public.admin_panel_scope() to authenticated;
grant execute on function public.admin_panel_matches(uuid, uuid) to authenticated;
