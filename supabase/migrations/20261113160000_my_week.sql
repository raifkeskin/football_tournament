-- "Bu hafta sen" kartı tek istekte.
--
-- Kart 4 sıralı tur atıyordu (esame + goller → maç → takım/kesit/medya/ödül
-- → yıldızlar; ~400-500 ms) ve Ana Sayfa'ya geç geliyordu. Bu fonksiyon aynı
-- veriyi tek cevapta döner. security invoker: erişim kuralları aynen uygulanır.
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
           x.home_score, x.away_score
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
  )
  select case when not exists (select 1 from m) then null else jsonb_build_object(
    'match', (select to_jsonb(m) from m),
    'my_team', (select ro.team_id from ro where ro.match_id = (select m.id from m) limit 1),
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
