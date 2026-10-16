-- VAR: gol iptali. Uygulama golün türünü 'goal' → 'goal_cancelled' yapar
-- (geri alınca tersi). Golü sayan her yer yalnız 'goal' saydığı için iptal
-- edilen gol skordan, gol krallığından ve istatistikten kendiliğinden düşer.
-- Bu tetikleyici maç skorunu golün yazıldığı tarafta 1 düşürür / artırır
-- (elle girilmiş skorlu eski maçlar bozulmasın diye yeniden hesaplamaz) ve
-- maç sürerken izleyenlere "VAR: Gol iptal" bildirimi gönderir.

create or replace function public.match_events_var_cancel()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_m record;
  v_side_home boolean;
  v_delta int;
  v_home int;
  v_away int;
  v_scorer text;
begin
  if old.event_type = new.event_type
     or old.event_type not in ('goal', 'goal_cancelled')
     or new.event_type not in ('goal', 'goal_cancelled') then
    return new;
  end if;

  select id, status, home_team_id, away_team_id, home_score, away_score
    into v_m
    from public.matches where id = new.match_id;
  if v_m.id is null then
    return new;
  end if;

  -- Golün yazıldığı taraf (kendi kalesine golde rakip).
  v_side_home := (new.team_id = v_m.home_team_id)
                 <> coalesce(new.is_own_goal, false);
  v_delta := case when new.event_type = 'goal_cancelled' then -1 else 1 end;
  v_home := greatest(coalesce(v_m.home_score, 0)
                     + case when v_side_home then v_delta else 0 end, 0);
  v_away := greatest(coalesce(v_m.away_score, 0)
                     + case when v_side_home then 0 else v_delta end, 0);

  update public.matches
     set home_score = v_home, away_score = v_away
   where id = new.match_id;

  -- Bildirim yalnız iptalde ve maç sürerken.
  if new.event_type = 'goal_cancelled'
     and v_m.status in ('live', 'halftime') then
    select trim(coalesce(name, '') || ' ' || coalesce(surname, ''))
      into v_scorer
      from public.players where id = new.player_id;
    perform public.push_send(
      public.match_audience(new.match_id, false),
      'VAR: Gol iptal',
      public.match_score_text(new.match_id, v_home, v_away)
        || ' · '
        || case when new.minute is not null
                then new.minute::text || '''' || ' ' else '' end
        || coalesce(nullif(v_scorer, ''), 'Gol')
        || ' golü iptal edildi',
      '/',
      'goal-' || new.match_id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists match_events_var_cancel on public.match_events;
create trigger match_events_var_cancel
  after update of event_type on public.match_events
  for each row execute function public.match_events_var_cancel();
