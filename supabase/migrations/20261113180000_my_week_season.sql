-- "Bu hafta sen" kartı (B tasarımı): sezon toplamları ve grup sırası.
--
-- my_week cevabına 'season' eklenir: oynadığı maç, galibiyet, gol, asist,
-- takımının grup sırası ve sezondaki grup sayısı. Ek istek gitmez. Eski
-- sürümler fazladan alanı yok sayar.
create or replace function public.my_week(p_league_id uuid, p_player_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with ev as (
    select e.id, e.match_id, e.player_id, e.assist_player_id, e.minute,
           e.added_minute, e.is_own_goal
      from public.match_events e
     where e.event_type = 'goal'
       and (e.player_id = p_player_id or e.assist_player_id = p_player_id)
       -- kendi kalesine attığı gol sayılmaz
       and not (e.is_own_goal is true and e.player_id = p_player_id)
  ),
  ro as (
    select r.match_id, r.team_id
      from public.match_rosters r
     where r.player_id = p_player_id
  ),
  -- Son 7 günde bu turnuvada oynadığı en son bitmiş maç.
  m as (
    select x.id, x.week, x.season_id, x.home_team_id, x.away_team_id,
           x.home_score, x.away_score, x.group_id, x.tiebreak
      from public.matches x
     where x.league_id = p_league_id
       and x.status = 'finished'
       and x.deleted_at is null
       and x.match_date >= current_date - 7
       and (x.id in (select ro.match_id from ro)
            or x.id in (select ev.match_id from ev))
     order by x.match_date desc
     limit 1
  ),
  here as (select ev.* from ev where ev.match_id = (select m.id from m)),
  med as (
    select x.id, x.url, x.media_type, x.team_id, x.created_at
      from public.match_media x
     where x.match_id = (select m.id from m)
       and x.media_type in ('Önemli An', 'Takım Fotosu')
     order by x.created_at
     limit 24
  ),
  me as (
    select (select ro.team_id from ro where ro.match_id = (select m.id from m) limit 1) as tid
  ),
  -- Sezon toplamları: oynadığı bitmiş maçlar, galibiyetler, gol ve asist.
  sm as (
    select x.id, x.home_team_id, x.away_team_id, x.home_score, x.away_score, ro.team_id
      from public.matches x
      join ro on ro.match_id = x.id
     where x.season_id = (select m.season_id from m)
       and x.status = 'finished'
       and x.deleted_at is null
  ),
  sev as (
    select ev.player_id
      from ev
      join public.matches x on x.id = ev.match_id
     where x.season_id = (select m.season_id from m)
       and x.status = 'finished'
       and x.deleted_at is null
  ),
  -- Grup sırası: uygulamadaki puan tablosuyla aynı kural
  -- (lib/features/team/utils/standings.dart): puan, ikili averaj (puan,
  -- gol farkı), genel averaj, atılan gol, ad. Eleme maçında sıra yok.
  gm as (
    select x.id, x.home_team_id, x.away_team_id, x.home_score, x.away_score,
           ((x.status = 'finished' or x.is_completed is true)
             and x.status not in ('cancelled', 'postponed')) as done
      from public.matches x
     where x.group_id = (select m.group_id from m)
       and (select m.tiebreak from m) is null
       and x.tiebreak is null
       and x.deleted_at is null
  ),
  gt as (
    select gm.home_team_id as tid from gm where gm.home_team_id is not null
    union
    select gm.away_team_id from gm where gm.away_team_id is not null
    union
    select st.team_id from public.season_teams st
     where st.group_id = (select m.group_id from m)
       and (select m.tiebreak from m) is null
  ),
  tb as (
    select gt.tid, lower(coalesce(t.name, '')) as name,
           coalesce(sum(case
             when f.id is null then 0
             when (f.home_team_id = gt.tid and f.home_score > f.away_score)
               or (f.away_team_id = gt.tid and f.away_score > f.home_score) then 3
             when f.home_score = f.away_score then 1
             else 0 end), 0) as pts,
           coalesce(sum(case when f.home_team_id = gt.tid then f.home_score
                             else f.away_score end), 0) as gf,
           coalesce(sum(case when f.home_team_id = gt.tid then f.away_score
                             else f.home_score end), 0) as ga
      from gt
      left join public.teams t on t.id = gt.tid
      left join gm f on f.done and gt.tid in (f.home_team_id, f.away_team_id)
     group by gt.tid, t.name
  ),
  rk as (
    select 1 + count(*) filter (where
             y.pts > i.pts
             or (y.pts = i.pts and (
               h.yp > h.ip
               or (h.yp = h.ip and (
                 h.gd > 0
                 or (h.gd = 0 and (
                   y.gf - y.ga > i.gf - i.ga
                   or (y.gf - y.ga = i.gf - i.ga and (
                     y.gf > i.gf
                     or (y.gf = i.gf and y.name < i.name)))))))))) as pos
      from tb i
      left join tb y on y.tid <> i.tid
      left join lateral (
        select coalesce(sum(case
                 when (f.home_team_id = y.tid and f.home_score > f.away_score)
                   or (f.away_team_id = y.tid and f.away_score > f.home_score) then 3
                 when f.home_score = f.away_score then 1 else 0 end), 0) as yp,
               coalesce(sum(case
                 when (f.home_team_id = i.tid and f.home_score > f.away_score)
                   or (f.away_team_id = i.tid and f.away_score > f.home_score) then 3
                 when f.home_score = f.away_score then 1 else 0 end), 0) as ip,
               coalesce(sum(case when f.home_team_id = y.tid
                                 then f.home_score - f.away_score
                                 else f.away_score - f.home_score end), 0) as gd
          from gm f
         where f.done
           and ((f.home_team_id = y.tid and f.away_team_id = i.tid)
             or (f.home_team_id = i.tid and f.away_team_id = y.tid))
      ) h on true
     where i.tid = (select me.tid from me)
  )
  select case when not exists (select 1 from m) then null else jsonb_build_object(
    'match', (select to_jsonb(m) from m),
    'my_team', (select me.tid from me),
    'season', jsonb_build_object(
      'played', (select count(*) from sm),
      'wins', (select count(*) from sm
                where (sm.team_id = sm.home_team_id and sm.home_score > sm.away_score)
                   or (sm.team_id = sm.away_team_id and sm.away_score > sm.home_score)),
      'goals', (select count(*) from sev where sev.player_id = p_player_id),
      'assists', (select count(*) from sev where sev.player_id is distinct from p_player_id),
      'rank', (select rk.pos from rk),
      'groups', (select count(distinct x.group_id) from public.matches x
                  where x.season_id = (select m.season_id from m)
                    and x.group_id is not null and x.deleted_at is null)),
    'events', coalesce((select jsonb_agg(to_jsonb(here)) from here), '[]'::jsonb),
    'teams', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'logo_url', t.logo_url))
        from public.teams t
       where t.id in ((select m.home_team_id from m), (select m.away_team_id from m))), '[]'::jsonb),
    'clips', coalesce((
      select jsonb_agg(jsonb_build_object(
               'match_event_id', h.match_event_id, 'video_id', h.video_id,
               'start_sec', h.start_sec, 'end_sec', h.end_sec,
               'clip_url', h.clip_url, 'story_url', h.story_url))
        from public.match_highlights h
       where h.match_id = (select m.id from m)
         and h.status = 'approved'
         and h.match_event_id in (select here.id from here)), '[]'::jsonb),
    'media', coalesce((
      select jsonb_agg(jsonb_build_object('id', med.id, 'url', med.url,
               'media_type', med.media_type, 'team_id', med.team_id)
               order by med.created_at)
        from med), '[]'::jsonb),
    'news', coalesce((
      select jsonb_agg(jsonb_build_object('auto_data', n.auto_data))
        from public.news n
       where n.season_id = (select m.season_id from m)
         and n.auto_kind = 'week_awards'
         and n.week = (select m.week from m)
         and n.is_published), '[]'::jsonb),
    'starred', coalesce((
      select jsonb_agg(s.media_id)
        from public.player_photo_stars s
       where s.player_id = p_player_id
         and s.media_id in (select med.id from med)), '[]'::jsonb)
  ) end;
$$;

revoke all on function public.my_week(uuid, uuid) from public, anon;
grant execute on function public.my_week(uuid, uuid) to authenticated, service_role;
