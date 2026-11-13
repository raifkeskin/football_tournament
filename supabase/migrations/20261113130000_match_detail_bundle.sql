-- Hız Faz 2B: maç detayı tek istekte.
--
-- Maç ekranı açılınca ~12 ayrı istek gidiyordu (maç, olaylar → oyuncu
-- adları, esame, iki takımın kadrosu → maçta oynayıp ayrılanlar, medya,
-- gol kesitleri, sezon ayarları; bazıları sıralı). Bu fonksiyon hepsini tek
-- cevapta döner; uygulama servis önbelleklerini bununla doldurur.
--
-- security invoker: her tabloda okuyanın erişim kuralları (RLS) aynen
-- uygulanır; görünmeyen maç için null döner. Oyuncu sütunları açıkça
-- seçilir (kişisel veri sütunları gelmez; uygulamadaki kPlayerColumns).
-- Açık/kapalı: app_settings.match_bundle_enabled (admin her zaman).

create or replace function public.match_detail_bundle(p_match_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with m as (
    select x.* from public.matches x where x.id = p_match_id
  ),
  sides as (
    select t.team_id
      from m, lateral (values (m.home_team_id), (m.away_team_id)) t(team_id)
     where t.team_id is not null
  ),
  names as (
    select p.id,
           nullif(concat_ws(' ', nullif(trim(p.name), ''),
                                 nullif(trim(p.surname), '')), '') as full_name
      from public.players p
     where p.id in (select e.player_id from public.match_events e where e.match_id = p_match_id
                    union select e.assist_player_id from public.match_events e where e.match_id = p_match_id
                    union select e.sub_in_player_id from public.match_events e where e.match_id = p_match_id)
  )
  select case when not exists (select 1 from m) then null else jsonb_build_object(
    'match', (select to_jsonb(m) from m),
    'events', coalesce((
      select jsonb_agg(
               to_jsonb(e) || jsonb_strip_nulls(jsonb_build_object(
                 'player_name', (select n.full_name from names n where n.id = e.player_id),
                 'assist_player_name', (select n.full_name from names n where n.id = e.assist_player_id),
                 'sub_in_player_name', (select n.full_name from names n where n.id = e.sub_in_player_id)))
               order by e.minute)
        from public.match_events e
       where e.match_id = p_match_id), '[]'::jsonb),
    'rosters', coalesce((
      select jsonb_agg(to_jsonb(r))
        from public.match_rosters r
       where r.match_id = p_match_id), '[]'::jsonb),
    'media', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.created_at desc)
        from public.match_media x
       where x.match_id = p_match_id), '[]'::jsonb),
    'highlights', coalesce((
      select jsonb_agg(to_jsonb(h) order by h.start_sec)
        from public.match_highlights h
       where h.match_id = p_match_id and h.status <> 'rejected'), '[]'::jsonb),
    'settings', (
      select jsonb_build_object(
               'match_period_duration', s.match_period_duration,
               'track_goal_minutes', s.track_goal_minutes,
               'ai_esame_enabled', s.ai_esame_enabled,
               'ai_clips_enabled', s.ai_clips_enabled,
               'assistant_referees_enabled', s.assistant_referees_enabled,
               'rolling_subs', s.rolling_subs)
        from public.seasons s
       where s.id = (select m.season_id from m)),
    -- Takım başına: sezon kadrosu (aktif) ve maçın esamesindeki oyuncular
    -- (sonradan takımdan ayrılan da görünsün). Satır biçimi uygulamadaki
    -- `jersey_number, players!inner(...)` sorgusuyla aynı.
    'players', coalesce((
      select jsonb_object_agg(sd.team_id, jsonb_build_object(
        'squad', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'jersey_number', stp.jersey_number,
                   'players', (select to_jsonb(q) from (
                      select p.id, p.name, p.surname, p.birth_date,
                             p.preferred_foot, p.main_position, p.sub_position,
                             p.photo_url, p.height, p.weight, p.auth_uid,
                             p.created_at, p.updated_at) q)))
            from public.season_team_players stp
            join public.players p on p.id = stp.player_id
           where stp.team_id = sd.team_id
             and stp.season_id = (select m.season_id from m)
             and stp.is_active), '[]'::jsonb),
        'played', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'jersey_number', r.jersey_number,
                   'players', (select to_jsonb(q) from (
                      select p.id, p.name, p.surname, p.birth_date,
                             p.preferred_foot, p.main_position, p.sub_position,
                             p.photo_url, p.height, p.weight, p.auth_uid,
                             p.created_at, p.updated_at) q)))
            from public.match_rosters r
            join public.players p on p.id = r.player_id
           where r.match_id = p_match_id
             and r.team_id = sd.team_id), '[]'::jsonb)))
        from sides sd), '{}'::jsonb)
  ) end;
$$;

revoke all on function public.match_detail_bundle(uuid) from public;
grant execute on function public.match_detail_bundle(uuid) to anon, authenticated, service_role;

-- Kapı: kapalıyken yalnız admin kullanır (uygulama tarafı).
insert into public.app_settings (key, value)
values ('match_bundle_enabled', 'false'::jsonb)
on conflict (key) do nothing;
