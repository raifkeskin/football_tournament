-- Sezon ayarı: oyundan çıkan oyuncu tekrar oyuna girebilir mi
-- (halısahada dönüşümlü değişiklik). Kapalıyken (büyük saha) çıkan oyuncu
-- yedeklerde görünür ama seçilemez; kural burada, tüm istemciler için tek.

alter table public.seasons
  add column if not exists rolling_subs boolean not null default false;

-- Bugüne kadar yeniden giriş serbestti: halısaha sezonlarında öyle kalsın.
update public.seasons set rolling_subs = true
 where coalesce(starting_player_count, 11) < 11 and not rolling_subs;

create or replace function public.match_events_check_substitution()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  on_pitch uuid[];
begin
  if new.event_type <> 'substitution' or new.team_id is null then
    return new;
  end if;
  if not exists (select 1 from public.match_rosters
                  where match_id = new.match_id and team_id = new.team_id) then
    return new;
  end if;
  on_pitch := public.match_on_pitch(new.match_id, new.team_id);
  if new.player_id is null or not (new.player_id = any(on_pitch)) then
    raise exception 'Çıkan oyuncu şu an sahada değil.' using errcode = '23514';
  end if;
  if new.sub_in_player_id is null
     or new.sub_in_player_id = any(on_pitch)
     or not exists (select 1 from public.match_rosters
                     where match_id = new.match_id and team_id = new.team_id
                       and player_id = new.sub_in_player_id) then
    raise exception 'Giren oyuncu kenardaki oyunculardan (yedeklerden) olmalı.' using errcode = '23514';
  end if;
  if exists (select 1 from public.match_events
              where match_id = new.match_id
                and player_id = new.sub_in_player_id
                and (event_type = 'red_card'
                     or (event_type = 'yellow_card'
                         and (select count(*) from public.match_events y
                               where y.match_id = new.match_id
                                 and y.event_type = 'yellow_card'
                                 and y.player_id = new.sub_in_player_id) >= 2))) then
    raise exception 'Oyundan atılan oyuncu tekrar giremez.' using errcode = '23514';
  end if;
  if exists (select 1 from public.match_events
              where match_id = new.match_id and event_type = 'substitution'
                and player_id = new.sub_in_player_id)
     and not coalesce((select s.rolling_subs from public.matches m
                         join public.seasons s on s.id = m.season_id
                        where m.id = new.match_id), false) then
    raise exception 'Bu turnuvada oyundan çıkan oyuncu tekrar oyuna giremez.' using errcode = '23514';
  end if;
  return new;
end;
$$;

-- Masa: yedek listesi bu ayara göre çıkan oyuncuyu kilitler.
CREATE OR REPLACE FUNCTION public.desk_match(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r jsonb;
begin
  if not public.can_manage_match(p_match_id) then
    raise exception 'Bu maçı yönetme yetkiniz yok.' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'id', m.id,
    'league_id', coalesce(m.league_id, s.league_id),
    'league', l.name,
    'season', s.name,
    'week', m.week,
    'cup_round', m.cup_round,
    'date', m.match_date,
    'time', m.match_time,
    'status', m.status,
    'tiebreak', m.tiebreak,
    'kickoff_at', m.kickoff_at,
    'second_half_at', m.second_half_at,
    'extra_time_at', m.extra_time_at,
    'shootout', m.shootout,
    'period', coalesce(nullif(s.match_period_duration, 0), 30),
    'track_minutes', coalesce(s.track_goal_minutes, true),
    'rolling_subs', coalesce(s.rolling_subs, false),
    'owner', public.owns_match(m.id),
    'home_id', m.home_team_id, 'home', ht.name, 'home_logo', ht.logo_url,
    'away_id', m.away_team_id, 'away', at.name, 'away_logo', at.logo_url,
    'hs', m.home_score, 'as', m.away_score,
    'home_formation', m.home_formation, 'away_formation', m.away_formation,
    'hp', m.home_pens, 'ap', m.away_pens,
    'now', now(),
    -- Esame (maç kadrosu): olaylar yalnız buradaki oyunculara girilir.
    'roster', coalesce((
      select jsonb_agg(jsonb_build_object(
        'team_id', mr.team_id, 'player_id', mr.player_id,
        'name', trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, '')),
        'no', mr.jersey_number, 'starting', coalesce(mr.is_starting, false),
        'captain', coalesce(mr.is_captain, false),
        'pos', p.main_position, 'pos2', p.sub_position, 'slot', mr.pos_x
      ) order by mr.is_starting desc, mr.jersey_number nulls last, p.name)
      from public.match_rosters mr
      join public.players p on p.id = mr.player_id
      where mr.match_id = m.id
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'type', e.event_type, 'minute', e.minute,
        'added', e.added_minute, 'assist_id', e.assist_player_id,
        'team_id', e.team_id, 'player_id', e.player_id,
        'player', trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, '')),
        'assist', trim(coalesce(pa.name, '') || ' ' || coalesce(pa.surname, '')),
        'sub_in', trim(coalesce(pi.name, '') || ' ' || coalesce(pi.surname, '')),
        'sub_in_id', e.sub_in_player_id,
        'own', coalesce(e.is_own_goal, false), 'pen', coalesce(e.is_penalty, false)
      ) order by e.minute nulls last, coalesce(e.added_minute, 0), e.created_at)
      from public.match_events e
      left join public.players p on p.id = e.player_id
      left join public.players pa on pa.id = e.assist_player_id
      left join public.players pi on pi.id = e.sub_in_player_id
      where e.match_id = m.id and e.event_type <> 'status'
    ), '[]'::jsonb)
  ) into r
  from public.matches m
  join public.seasons s on s.id = m.season_id
  left join public.leagues l on l.id = coalesce(m.league_id, s.league_id)
  left join public.teams ht on ht.id = m.home_team_id
  left join public.teams at on at.id = m.away_team_id
  where m.id = p_match_id;
  return r;
end;
$function$;
