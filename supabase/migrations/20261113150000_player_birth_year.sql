-- Doğum tarihi gizliliği (1. adım): herkese açık alan doğum YILI olur.
--
-- Bugün tam doğum tarihi (gün-ay-yıl) herkese açık anahtarla okunabiliyor.
-- Uygulamanın ihtiyacı yalnız yıl (yaş, kontenjan). Yeni sürüm birth_year
-- okur; tam tarihi yalnız admin ve oyuncunun kendisi player_birth_date() ile
-- görür. 2. adım (yeni sürüm yayıldıktan SONRA, ayrı betik): birth_date
-- sütununun okuma yetkisi anon/authenticated'dan kaldırılır.

alter table public.players
  add column if not exists birth_year smallint
  generated always as (extract(year from birth_date)::smallint) stored;

-- players'ta okuma sütun düzeyinde (bkz. manual/players_revoke_phone.sql):
-- yeni sütun ayrıca verilir.
grant select (birth_year) on public.players to anon, authenticated;

create or replace function public.player_birth_date(p_player_id uuid)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select p.birth_date
    from public.players p
   where p.id = p_player_id
     and (public.is_admin() or p.auth_uid = (select auth.uid()));
$$;
revoke all on function public.player_birth_date(uuid) from public, anon;
grant execute on function public.player_birth_date(uuid) to authenticated, service_role;

-- Maç detayı paketi: oyuncu satırında doğum tarihi yerine doğum yılı.
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
                      select p.id, p.name, p.surname, p.birth_year,
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
                      select p.id, p.name, p.surname, p.birth_year,
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
