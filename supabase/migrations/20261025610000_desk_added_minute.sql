-- Yönetim Masası: uzatma dakikası (45+2') ve olay düzenleme için olaylar
-- added_minute ve asist kimliğiyle döner; desk_add_event uzatmayı yazar.
drop function if exists public.desk_add_event(uuid, text, uuid, uuid, integer, uuid, uuid, boolean, boolean);

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
    'owner', public.owns_match(m.id),
    'home_id', m.home_team_id, 'home', ht.name, 'home_logo', ht.logo_url,
    'away_id', m.away_team_id, 'away', at.name, 'away_logo', at.logo_url,
    'hs', m.home_score, 'as', m.away_score,
    'hp', m.home_pens, 'ap', m.away_pens,
    'now', now(),
    -- Esame (maç kadrosu): olaylar yalnız buradaki oyunculara girilir.
    'roster', coalesce((
      select jsonb_agg(jsonb_build_object(
        'team_id', mr.team_id, 'player_id', mr.player_id,
        'name', trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, '')),
        'no', mr.jersey_number, 'starting', coalesce(mr.is_starting, false),
        'captain', coalesce(mr.is_captain, false)
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

CREATE OR REPLACE FUNCTION public.desk_add_event(p_match_id uuid, p_type text, p_team_id uuid, p_player_id uuid, p_minute integer DEFAULT NULL::integer, p_assist_id uuid DEFAULT NULL::uuid, p_sub_in_id uuid DEFAULT NULL::uuid, p_own_goal boolean DEFAULT false, p_penalty boolean DEFAULT false, p_added integer DEFAULT NULL::integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  m public.matches;
  v_id uuid;
  v_home boolean;
begin
  if not public.can_manage_match(p_match_id) then
    raise exception 'Bu maçı yönetme yetkiniz yok.' using errcode = '42501';
  end if;
  if p_type not in ('goal', 'penalty_missed', 'yellow_card', 'red_card',
                    'substitution', 'man_of_the_match') then
    raise exception 'Bilinmeyen olay türü: %', p_type;
  end if;
  select * into m from public.matches where id = p_match_id for update;
  if not found then
    raise exception 'Maç bulunamadı.';
  end if;
  if p_team_id not in (m.home_team_id, m.away_team_id) then
    raise exception 'Takım bu maçta oynamıyor.';
  end if;
  if p_type = 'substitution' and p_sub_in_id is null then
    raise exception 'Giren oyuncuyu seçin.';
  end if;

  insert into public.match_events (match_id, team_id, player_id, event_type,
    minute, added_minute, assist_player_id, sub_in_player_id, is_own_goal, is_penalty, created_at)
  values (p_match_id, p_team_id, p_player_id, p_type,
    case when p_type = 'man_of_the_match' then 999 else p_minute end,
    case when p_type <> 'man_of_the_match' and p_added > 0 then least(p_added, 30) end,
    case when p_type = 'goal' and not p_own_goal then p_assist_id end,
    case when p_type = 'substitution' then p_sub_in_id end,
    p_type = 'goal' and p_own_goal,
    p_type = 'goal' and p_penalty and not p_own_goal,
    now())
  returning id into v_id;

  if m.status = 'finished' then
    perform public.desk_sync_finished_score(p_match_id, false);
  elsif p_type = 'goal' then
    v_home := (p_team_id = m.home_team_id) <> p_own_goal;
    update public.matches
       set home_score = coalesce(home_score, 0) + case when v_home then 1 else 0 end,
           away_score = coalesce(away_score, 0) + case when v_home then 0 else 1 end
     where id = p_match_id;
  end if;
  return v_id;
end;
$function$;

grant execute on function public.desk_add_event(uuid, text, uuid, uuid, integer, uuid, uuid, boolean, boolean, integer) to authenticated;
revoke all on function public.desk_add_event(uuid, text, uuid, uuid, integer, uuid, uuid, boolean, boolean, integer) from public, anon;
