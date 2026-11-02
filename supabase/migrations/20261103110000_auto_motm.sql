-- Otomatik maçın oyuncusu: demo turnuvalarda ve auto_motm_leagues'deki
-- turnuvalarda (Hürriyet) bitmiş maçın elle seçilmiş maçın adamı yoksa,
-- puanı en yüksek oyuncu maçın adamı olarak kaydedilir. Puan hesabı
-- uygulamadaki MatchInsights.ratingFor ile aynıdır (lib/features/match/
-- insights/match_insights.dart). Champions gibi diğer turnuvalarda kayıt
-- yalnız adminin "Onayla"sıyla olur. Olay eklemek bildirim ya da haber
-- üretmez (gol tetikleyicileri yalnız 'goal' olayında çalışır).

-- Mevkiden saha hattı (formation_tab.dart positionLineOf): 0 kaleci,
-- 1 defans, 2 orta saha (bilinmeyen dahil), 3 forvet.
create or replace function public._position_line(p_main text, p_sub text)
returns int
language sql
immutable
set search_path to ''
as $$
  select coalesce((
    select case
      when p like '%kaleci%' or p = 'gk' then 0
      when p like '%forvet%' or p like '%santrfor%' or p = 'for' then 3
      when p like '%defans%' or p like '%stoper%' or p like '%bek%' or p = 'def' then 1
      when p like '%orta%' or p like '%numara%' or p like '%kanat%' or p like '%merkez%'
           or p = 'ort' then 2
    end
    from (select lower(trim(coalesce(x, ''))) as p, i
            from unnest(array[p_main, p_sub]) with ordinality as u(x, i)) t
   where p <> ''
     and (p like '%kaleci%' or p = 'gk' or p like '%forvet%' or p like '%santrfor%'
          or p = 'for' or p like '%defans%' or p like '%stoper%' or p like '%bek%'
          or p = 'def' or p like '%orta%' or p like '%numara%' or p like '%kanat%'
          or p like '%merkez%' or p = 'ort')
   order by i
   limit 1), 2)
$$;

-- Puanı en yüksek oyuncu (eşitlikte gol, sonra asist). Puanlama kapalıysa
-- ya da maç bitmemişse null.
create or replace function public.auto_motm_pick(p_match uuid)
returns table (player_id uuid, team_id uuid, rating numeric)
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  m public.matches%rowtype;
  v_rules jsonb;
  v_end int;
begin
  select * into m from public.matches where id = p_match;
  if m.id is null or m.status <> 'finished' then
    return;
  end if;
  select s.player_rating,
         coalesce(nullif(s.match_period_duration, 0), 45) * 2
    into v_rules, v_end
    from public.seasons s where s.id = m.season_id;
  if coalesce((v_rules ->> 'enabled')::boolean, false) is not true then
    return;
  end if;

  return query
  with rv as (
    select k, coalesce((v_rules -> 'rules' ->> k)::numeric, d) as v
      from (values ('base', 7.0), ('goal', 1.0), ('pen_goal', 0.7), ('assist', 0.5),
                   ('win', 0.3), ('loss', -0.3), ('cs_gk', 1.0), ('cs_def', 0.5),
                   ('motm', 0.5), ('yellow', -0.5), ('second_yellow', -1.0),
                   ('red', -2.0), ('own_goal', -1.0), ('min_minutes', 10),
                   ('sub_base', 6.5), ('full_bonus', 0.2), ('cs_minutes', 60)) x(k, d)
  ), r as (select jsonb_object_agg(k, v) as j from rv),
  ro as (
    select mr.player_id, mr.team_id, coalesce(mr.is_starting, false) as starter,
           coalesce(mr.list_order, 999) as ord, mr.created_at,
           public._position_line(p.main_position, p.sub_position) as pline
      from public.match_rosters mr
      join public.players p on p.id = mr.player_id
     where mr.match_id = p_match and mr.team_id in (m.home_team_id, m.away_team_id)
  ),
  gk as (
    -- Sahadaki kaleci: ilk 11'de kaleci mevkili ilk oyuncu, yoksa ilk 11'in ilki.
    select distinct on (ro.team_id) ro.team_id, ro.player_id
      from ro where ro.starter
     order by ro.team_id, (ro.pline <> 0), ro.ord, ro.created_at
  ),
  ev as (
    select e.player_id as pid,
           count(*) filter (where e.event_type = 'goal' and not coalesce(e.is_own_goal, false)
                                   and not coalesce(e.is_penalty, false)) as goals,
           count(*) filter (where e.event_type = 'goal' and not coalesce(e.is_own_goal, false)
                                   and coalesce(e.is_penalty, false)) as pens,
           count(*) filter (where e.event_type = 'goal' and coalesce(e.is_own_goal, false)) as owns,
           count(*) filter (where e.event_type = 'yellow_card') as yellows,
           count(*) filter (where e.event_type = 'red_card') as reds,
           min(e.minute) filter (where e.event_type = 'red_card') as red_min,
           bool_or(e.event_type = 'substitution') as subbed_out,
           min(e.minute) filter (where e.event_type = 'substitution') as out_min,
           bool_or(e.event_type = 'man_of_the_match') as motm
      from public.match_events e where e.match_id = p_match and e.player_id is not null
     group by e.player_id
  ),
  asg as (
    select e.assist_player_id as pid, count(*) as assists
      from public.match_events e
     where e.match_id = p_match and e.event_type = 'goal'
       and not coalesce(e.is_own_goal, false) and e.assist_player_id is not null
     group by 1
  ),
  sin as (
    select e.sub_in_player_id as pid, min(e.minute) as in_min
      from public.match_events e
     where e.match_id = p_match and e.event_type = 'substitution'
       and e.sub_in_player_id is not null
     group by 1
  ),
  mo as (
    select mm.player_id as pid,
           sum(coalesce((v_rules -> 'moments' ->> mm.kind)::numeric,
             case mm.kind
               when 'save' then 0.3 when 'one_on_one' then 0.5 when 'pen_save' then 1.0
               when 'gk_error' then -0.5 when 'tackle' then 0.3 when 'line_clear' then 0.5
               when 'interception' then 0.2 when 'pen_conceded' then -0.5
               when 'key_pass' then 0.3 when 'recovery' then 0.2 when 'woodwork' then 0.2
               when 'bad_loss' then -0.5 when 'pen_won' then 0.5 when 'big_miss' then -0.3
               when 'pen_miss' then -1.0 when 'error_goal' then -1.0 else 0 end)) as pts
      from public.match_moments mm where mm.match_id = p_match group by 1
  ),
  base as (
    select ro.player_id, ro.team_id, ro.starter, ro.ord,
           (ro.team_id = m.home_team_id) as home,
           case when ro.starter and gk.player_id = ro.player_id then 0
                when ro.pline = 0 then 1 else ro.pline end as line,
           coalesce(ev.goals, 0) as goals, coalesce(ev.pens, 0) as pens,
           coalesce(ev.owns, 0) as owns, coalesce(asg.assists, 0) as assists,
           coalesce(ev.yellows, 0) as yellows, coalesce(ev.reds, 0) as reds,
           ev.red_min, coalesce(ev.subbed_out, false) as subbed_out, ev.out_min,
           coalesce(ev.motm, false) as motm, sin.pid is not null as subbed_in, sin.in_min,
           coalesce(mo.pts, 0) as moments
      from ro
      left join gk on gk.team_id = ro.team_id
      left join ev on ev.pid = ro.player_id
      left join asg on asg.pid = ro.player_id
      left join sin on sin.pid = ro.player_id
      left join mo on mo.pid = ro.player_id
  ),
  played as (
    select b.*,
           greatest(0,
             least(case when b.subbed_out then coalesce(b.out_min, v_end) else v_end end,
                   case when b.reds > 0 then coalesce(b.red_min, v_end) else v_end end)
             - case when b.starter then 0 else coalesce(b.in_min, v_end) end) as mins
      from base b
     where b.starter or b.subbed_in
  ),
  rated as (
    select pl.player_id, pl.team_id, pl.home, pl.ord, pl.goals + pl.pens as g, pl.assists,
           round(least(10, greatest(3,
             case when pl.starter then (r.j->>'base')::numeric else (r.j->>'sub_base')::numeric end
             + (r.j->>'goal')::numeric * pl.goals
             + (r.j->>'pen_goal')::numeric * pl.pens
             + (r.j->>'assist')::numeric * pl.assists
             + (r.j->>'own_goal')::numeric * pl.owns
             + case when pl.motm then (r.j->>'motm')::numeric else 0 end
             + case when pl.reds > 0 and pl.yellows > 0
                    then (r.j->>'second_yellow')::numeric + (r.j->>'yellow')::numeric * (pl.yellows - 1)
                    else (r.j->>'yellow')::numeric * pl.yellows + (r.j->>'red')::numeric * pl.reds end
             + case when pl.mins >= 60 then (r.j->>'full_bonus')::numeric else 0 end
             + case when (case when pl.home then m.home_score else m.away_score end)
                         > (case when pl.home then m.away_score else m.home_score end)
                    then (r.j->>'win')::numeric
                    when (case when pl.home then m.home_score else m.away_score end)
                         < (case when pl.home then m.away_score else m.home_score end)
                    then (r.j->>'loss')::numeric else 0 end
             + case when (case when pl.home then m.away_score else m.home_score end) = 0
                         and pl.mins >= (r.j->>'cs_minutes')::numeric
                    then case pl.line when 0 then (r.j->>'cs_gk')::numeric
                                      when 1 then (r.j->>'cs_def')::numeric else 0 end
                    else 0 end
             + pl.moments)), 1) as rating
      from played pl, r
     where pl.mins >= (r.j->>'min_minutes')::numeric
  )
  select x.player_id, x.team_id, x.rating
    from rated x
   order by x.rating desc, x.g desc, x.assists desc, x.home desc, x.ord
   limit 1;
end;
$$;

-- Maçın adamı yoksa puandan seçileni kaydeder. Kaydedilirse oyuncu id'si.
create or replace function public.auto_motm_apply(p_match uuid)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  m public.matches%rowtype;
  c record;
begin
  select * into m from public.matches where id = p_match for update;
  if m.id is null or m.status <> 'finished'
     or exists (select 1 from public.match_events
                 where match_id = p_match and event_type = 'man_of_the_match') then
    return null;
  end if;
  select * into c from public.auto_motm_pick(p_match);
  if c.player_id is null then
    return null;
  end if;
  insert into public.match_events (match_id, season_id, team_id, player_id,
                                   event_type, minute, event_name, created_at)
  select p_match, m.season_id, c.team_id, c.player_id,
         'man_of_the_match', 999, trim(p.name || ' ' || p.surname), now()
    from public.players p where p.id = c.player_id;
  return c.player_id;
end;
$$;

revoke all on function public.auto_motm_pick(uuid) from public, anon, authenticated;
revoke all on function public.auto_motm_apply(uuid) from public, anon, authenticated;

-- Otomatik turnuvalar: demo turnuvalar + bu listedekiler.
insert into public.app_settings (key, value)
values ('auto_motm_leagues', '["c0da91c6-6bd4-4142-b255-33fb7b4c8886"]'::jsonb)
on conflict (key) do nothing;

-- Bu turnuvalarda puanlama açılır (varsayılan kurallar; puanlar herkese
-- ancak match_insights_enabled açılınca görünür).
update public.seasons s
   set player_rating = coalesce(s.player_rating, '{}'::jsonb) || '{"enabled": true}'::jsonb
  from public.leagues l
 where l.id = s.league_id
   and (l.is_demo
        or l.id::text in (select jsonb_array_elements_text(value)
                            from public.app_settings where key = 'auto_motm_leagues'))
   and coalesce((s.player_rating ->> 'enabled')::boolean, false) is not true;

-- Bitmiş ve detayları tamamlanmış maçlar: 30 dk bekleyip (son olaylar
-- girilsin) maçın adamı yoksa kaydeder. Geriye dönük de çalışır.
create or replace function public.auto_motm_run()
returns int
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id uuid;
  n int := 0;
begin
  for v_id in
    select m.id
      from public.matches m
      join public.leagues l on l.id = m.league_id
     where m.status = 'finished'
       and not coalesce(m.details_pending, false)
       and m.updated_at < now() - interval '30 minutes'
       and (l.is_demo
            or l.id::text in (select jsonb_array_elements_text(value)
                                from public.app_settings where key = 'auto_motm_leagues'))
       and not exists (select 1 from public.match_events e
                        where e.match_id = m.id and e.event_type = 'man_of_the_match')
     limit 50
  loop
    if public.auto_motm_apply(v_id) is not null then
      n := n + 1;
    end if;
  end loop;
  return n;
end;
$$;

revoke all on function public.auto_motm_run() from public, anon, authenticated;

select cron.unschedule('auto-motm') where exists (select 1 from cron.job where jobname = 'auto-motm');
select cron.schedule('auto-motm', '*/15 * * * *', 'select public.auto_motm_run()');
