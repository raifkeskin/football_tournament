-- Yönetim Masası, canlı maç: maçın tamamı tek istekte; olay ekleme/silme
-- ile skor aynı işlemde (uygulamadaki gibi okuyup yazmak yerine atomik
-- artış: iki kişi aynı anda gol girerse skor kaymaz). Yetki maç olaylarının
-- RLS kuralıyla aynı: can_manage_match (admin, turnuva sahibi, bölge
-- sorumlusu, maçın gözlemcisi).

-- Bitmiş maçta skor gollerden yeniden hesaplanır (uygulamadaki
-- _syncFinishedScore). Golü hiç girilmemiş, yalnız skoru yazılmış maçta
-- (gol yok ve gol silinmedi) skora dokunulmaz.
create or replace function public.desk_sync_finished_score(
  p_match_id uuid, p_goal_removed boolean)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  m public.matches;
  n int;
  h int;
  a int;
begin
  select * into m from public.matches where id = p_match_id;
  select count(*),
         count(*) filter (where (e.team_id = m.home_team_id) <> coalesce(e.is_own_goal, false)),
         count(*) filter (where (e.team_id = m.away_team_id) <> coalesce(e.is_own_goal, false))
    into n, h, a
    from public.match_events e
   where e.match_id = p_match_id and e.event_type = 'goal';
  if n = 0 and not p_goal_removed then
    return;
  end if;
  if m.home_score is distinct from h or m.away_score is distinct from a then
    update public.matches set home_score = h, away_score = a where id = p_match_id;
  end if;
end;
$$;
revoke all on function public.desk_sync_finished_score(uuid, boolean) from public, anon, authenticated;

create or replace function public.desk_match(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $$
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
        'team_id', e.team_id, 'player_id', e.player_id,
        'player', trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, '')),
        'assist', trim(coalesce(pa.name, '') || ' ' || coalesce(pa.surname, '')),
        'sub_in', trim(coalesce(pi.name, '') || ' ' || coalesce(pi.surname, '')),
        'sub_in_id', e.sub_in_player_id,
        'own', coalesce(e.is_own_goal, false), 'pen', coalesce(e.is_penalty, false)
      ) order by e.minute nulls last, e.created_at)
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
$$;
revoke all on function public.desk_match(uuid) from public, anon;
grant execute on function public.desk_match(uuid) to authenticated;

-- Olay ekle. p_team_id olayı yapan oyuncunun takımı (kendi kalesine golde
-- de); skor golün yazıldığı tarafa eklenir.
create or replace function public.desk_add_event(
  p_match_id uuid,
  p_type text,
  p_team_id uuid,
  p_player_id uuid,
  p_minute int default null,
  p_assist_id uuid default null,
  p_sub_in_id uuid default null,
  p_own_goal boolean default false,
  p_penalty boolean default false)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
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
    minute, assist_player_id, sub_in_player_id, is_own_goal, is_penalty, created_at)
  values (p_match_id, p_team_id, p_player_id, p_type,
    case when p_type = 'man_of_the_match' then 999 else p_minute end,
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
$$;
revoke all on function public.desk_add_event(uuid, text, uuid, uuid, int, uuid, uuid, boolean, boolean) from public, anon;
grant execute on function public.desk_add_event(uuid, text, uuid, uuid, int, uuid, uuid, boolean, boolean) to authenticated;

-- Yanlış girilen olayı sil; gol ise skor geri alınır.
create or replace function public.desk_delete_event(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  e public.match_events;
  m public.matches;
  v_home boolean;
begin
  select * into e from public.match_events where id = p_event_id;
  if not found then
    return;
  end if;
  if not public.can_manage_match(e.match_id) then
    raise exception 'Bu maçı yönetme yetkiniz yok.' using errcode = '42501';
  end if;
  select * into m from public.matches where id = e.match_id for update;
  delete from public.match_events where id = p_event_id;

  if m.status = 'finished' then
    perform public.desk_sync_finished_score(e.match_id, e.event_type = 'goal');
  elsif e.event_type = 'goal' then
    v_home := (e.team_id = m.home_team_id) <> coalesce(e.is_own_goal, false);
    update public.matches
       set home_score = greatest(coalesce(home_score, 0) - case when v_home then 1 else 0 end, 0),
           away_score = greatest(coalesce(away_score, 0) - case when v_home then 0 else 1 end, 0)
     where id = e.match_id;
  end if;
end;
$$;
revoke all on function public.desk_delete_event(uuid) from public, anon;
grant execute on function public.desk_delete_event(uuid) to authenticated;
