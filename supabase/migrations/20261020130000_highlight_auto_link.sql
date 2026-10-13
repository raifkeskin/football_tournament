-- YZ gol kesitleri gol kayıtlarıyla otomatik eşleşsin.
-- Kesit gol satırında ancak bir gol kaydına bağlıysa (match_event_id) izlenir.
-- Tam taramada (maç detayında gol yokken) kesitler bağsız kalıyordu; gol
-- sonradan girilince ya da kesit sonradan eklenince eşleştirme kendiliğinden
-- yapılır: aynı takım (golden yararlanan; kendi kalesine golde rakip) ve en
-- çok ±2 dakika fark, en yakın olan önce. Reddedilen kesit bağlanmaz; elle
-- bağlanmış kesite dokunulmaz.

create or replace function public.link_match_highlights(p_match_id uuid)
returns int
language plpgsql
security definer
set search_path to ''
as $$
declare
  m record;
  r record;
  v_linked int := 0;
  v_used_events uuid[] := '{}';
  v_used_hl uuid[] := '{}';
begin
  select id, home_team_id, away_team_id into m
    from public.matches where id = p_match_id;
  if m.id is null then
    return 0;
  end if;

  for r in
    with goals as (
      select e.id, e.minute,
             case when coalesce(e.is_own_goal, false) then
               case when e.team_id = m.home_team_id then m.away_team_id
                    else m.home_team_id end
             else e.team_id end as scoring_team
        from public.match_events e
       where e.match_id = p_match_id
         and e.event_type = 'goal'
         and e.minute is not null
         and not exists (select 1 from public.match_highlights h
                          where h.match_event_id = e.id)
    ),
    hls as (
      select h.id, h.minute, h.team_id
        from public.match_highlights h
       where h.match_id = p_match_id
         and h.match_event_id is null
         and h.status <> 'rejected'
         and h.kind = 'goal'
         and h.minute is not null
    )
    select g.id as event_id, h.id as hl_id,
           abs(g.minute - h.minute) as diff
      from goals g
      join hls h
        on abs(g.minute - h.minute) <= 2
       and (h.team_id is null or h.team_id = g.scoring_team)
     order by abs(g.minute - h.minute), h.minute
  loop
    if r.event_id = any(v_used_events) or r.hl_id = any(v_used_hl) then
      continue;
    end if;
    update public.match_highlights
       set match_event_id = r.event_id
     where id = r.hl_id and match_event_id is null;
    v_used_events := v_used_events || r.event_id;
    v_used_hl := v_used_hl || r.hl_id;
    v_linked := v_linked + 1;
  end loop;
  return v_linked;
end;
$$;

revoke all on function public.link_match_highlights(uuid) from public, anon;

-- Gol girilince / dakikası, takımı değişince.
create or replace function public.match_events_link_highlights()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.event_type = 'goal' then
    perform public.link_match_highlights(new.match_id);
  end if;
  return null;
end;
$$;

drop trigger if exists match_events_link_highlights on public.match_events;
create trigger match_events_link_highlights
  after insert or update of minute, team_id, event_type, is_own_goal
  on public.match_events
  for each row execute function public.match_events_link_highlights();

-- YZ kesit ekleyince (tam taramada gol kayıtları sonradan da olabilir).
create or replace function public.match_highlights_link()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform public.link_match_highlights(new.match_id);
  return null;
end;
$$;

drop trigger if exists match_highlights_link on public.match_highlights;
create trigger match_highlights_link
  after insert on public.match_highlights
  for each row execute function public.match_highlights_link();

-- Mevcut bağsız kesitler için bir kez.
select public.link_match_highlights(m.id)
  from public.matches m
 where exists (select 1 from public.match_highlights h
                where h.match_id = m.id and h.match_event_id is null);
