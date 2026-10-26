-- Gol bildirimi: skor ilk satırda, dakika + atan (asist) alt satırda.
CREATE OR REPLACE FUNCTION public.match_events_goal_push()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_m record;
  v_home int;
  v_away int;
  v_scorer text;
  v_assist text;
  v_body text;
begin
  if new.event_type <> 'goal' then
    return new;
  end if;
  select id, status, home_team_id, away_team_id into v_m
    from public.matches where id = new.match_id;
  if v_m.id is null or v_m.status not in ('live', 'halftime') then
    return new;
  end if;

  select
    count(*) filter (where (e.team_id = v_m.home_team_id and not coalesce(e.is_own_goal, false))
                        or (e.team_id = v_m.away_team_id and coalesce(e.is_own_goal, false))),
    count(*) filter (where (e.team_id = v_m.away_team_id and not coalesce(e.is_own_goal, false))
                        or (e.team_id = v_m.home_team_id and coalesce(e.is_own_goal, false)))
    into v_home, v_away
    from public.match_events e
   where e.match_id = new.match_id and e.event_type = 'goal';

  select trim(coalesce(name, '') || ' ' || coalesce(surname, '')) into v_scorer
    from public.players where id = new.player_id;
  select trim(coalesce(name, '') || ' ' || coalesce(surname, '')) into v_assist
    from public.players where id = new.assist_player_id;

  v_body := public.match_score_text(new.match_id, v_home, v_away)
    || E'\n'
    || coalesce(public.minute_label(new.minute, new.added_minute) || ' ', '')
    || coalesce(nullif(v_scorer, ''), 'Gol')
    || case when coalesce(new.is_own_goal, false) then ' (K.K.)'
            when coalesce(new.is_penalty, false) then ' (P)' else '' end
    || case when nullif(v_assist, '') is not null
            then ' (Asist: ' || v_assist || ')' else '' end;

  perform public.push_send(
    public.match_audience(new.match_id, false),
    'GOL!',
    v_body,
    '/',
    'goal-' || new.match_id
  );
  return new;
end;
$function$

;
