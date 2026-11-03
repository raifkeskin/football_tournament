-- Haftanın Enleri bülteni: kurucu başkan / bölge sorumlusu bir haftanın
-- 11'ini ve enlerini (oyuncusu, kalecisi, centilmeni, golü, maçı, takımı)
-- seçer; seçim tek haber (auto_kind 'week_awards') olarak yayınlanır. Hangi
-- enlerin bültende yer alacağına her hafta sorumlu karar verir.
-- Adaylar maç puanından gelir (match_player_ratings; auto_motm_pick ile aynı
-- formül). Puanlar kartta yalnız match_insights_enabled açıksa görünür.
-- Herkese açılana dek (week_awards_enabled) yalnız admin yayınlayabilir.

-- Maçta oynayan her oyuncunun puanı. p_any: sezonda puanlama kapalı olsa da
-- (varsayılan kurallarla) hesapla.
create or replace function public.match_player_ratings(p_match uuid, p_any boolean default false)
returns table (
  player_id uuid, team_id uuid, home boolean, ord int, line int, starter boolean,
  mins int, goals int, assists int, yellows int, reds int, conceded int, rating numeric
)
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
  if not p_any and coalesce((v_rules ->> 'enabled')::boolean, false) is not true then
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
  )
  select pl.player_id, pl.team_id, pl.home, pl.ord::int, pl.line::int, pl.starter,
         pl.mins::int, (pl.goals + pl.pens)::int, pl.assists::int, pl.yellows::int,
         pl.reds::int,
         (case when pl.home then m.away_score else m.home_score end)::int,
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
           + pl.moments)), 1)
    from played pl, r
   where pl.mins >= (r.j->>'min_minutes')::numeric;
end;
$$;

revoke all on function public.match_player_ratings(uuid, boolean) from public, anon, authenticated;

-- Maçın oyuncusu önerisi artık ortak puan fonksiyonundan.
create or replace function public.auto_motm_pick(p_match uuid)
returns table (player_id uuid, team_id uuid, rating numeric)
language sql
stable
security definer
set search_path to ''
as $$
  select x.player_id, x.team_id, x.rating
    from public.match_player_ratings(p_match) x
   order by x.rating desc, x.goals desc, x.assists desc, x.home desc, x.ord
   limit 1
$$;

revoke all on function public.auto_motm_pick(uuid) from public, anon, authenticated;

-- Kayıtlı dizilişte saha sırasının (pos_x) hattı: 0 kaleci, ilk hat defans,
-- son hat forvet, aradakiler orta saha. Diziliş geçersizse null.
create or replace function public._formation_line(p_formation text, p_slot int)
returns int
language sql
immutable
set search_path to ''
as $$
  select case
    when p_slot is null or p_slot < 0 then null
    when p_slot = 0 then 0
    when coalesce(p_formation, '') !~ '^[0-9]+(-[0-9]+)+$' then null
    else (
      select case when c.i = 1 then 1 when c.i = c.n then 3 else 2 end
        from (select u.i, count(*) over () as n,
                     sum(u.k::int) over (order by u.i) as cum
                from unnest(string_to_array(p_formation, '-')) with ordinality as u(k, i)) c
       where c.cum >= p_slot
       order by c.i
       limit 1)
  end
$$;

-- Haftanın aday havuzu: o hafta (bölgede) biten maçlarda oynayan herkes,
-- puanı ve maç istatistiğiyle. Yalnız bülteni yayınlayabilenler okur.
create or replace function public.week_award_pool(p_season_id uuid, p_region_id uuid, p_week int)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  if not (public.is_admin() or public.owns_news(p_season_id, p_region_id)) then
    raise exception 'Bu turnuvada bülten hazırlama yetkiniz yok.';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'player_id', x.player_id, 'team_id', x.team_id, 'match_id', mt.id,
             'line', coalesce(
               case when x.starter then public._formation_line(
                 case when x.home then mt.home_formation else mt.away_formation end,
                 mr.pos_x::int) end,
               case when x.starter and mr.pos_x = 0 then 0 end,
               x.line),
             'starter', x.starter, 'mins', x.mins,
             'goals', x.goals, 'assists', x.assists, 'yellows', x.yellows,
             'reds', x.reds, 'conceded', x.conceded, 'rating', x.rating,
             'number', mr.jersey_number)
           order by x.rating desc, x.goals desc)
      from public.matches mt
      left join public.groups g on g.id = mt.group_id
      cross join lateral public.match_player_ratings(mt.id, true) x
      left join public.match_rosters mr
             on mr.match_id = mt.id and mr.player_id = x.player_id
     where mt.season_id = p_season_id
       and mt.week = p_week
       and mt.status = 'finished'
       and mt.deleted_at is null
       and (p_region_id is null or g.region_id = p_region_id)
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.week_award_pool(uuid, uuid, int) from public, anon;
grant execute on function public.week_award_pool(uuid, uuid, int) to authenticated;

-- Haber türü ve her hafta (sezon, bölge) için tek bülten.
alter table public.news drop constraint if exists news_auto_kind_check;
alter table public.news add constraint news_auto_kind_check check (
  auto_kind = any (array[
    'match_result', 'week_results', 'instagram', 'match_preview',
    'day_preview', 'goal_of_week', 'player_of_week', 'team_of_week',
    'week_awards'
  ]::text[])
);

create unique index if not exists news_week_awards_uq on public.news (
  season_id,
  coalesce(region_id, '00000000-0000-0000-0000-000000000000'::uuid),
  week
) where auto_kind = 'week_awards';

insert into public.app_settings (key, value)
values ('week_awards_enabled', 'false'::jsonb)
on conflict (key) do nothing;

create or replace function public.publish_week_awards(
  p_season_id uuid,
  p_region_id uuid,
  p_week int,
  p_content text,
  p_image_url text,
  p_data jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_img text := nullif(trim(coalesce(p_image_url, '')), '');
begin
  if not (public.is_admin() or coalesce((
    select s.value = 'true'::jsonb from public.app_settings s
    where s.key = 'week_awards_enabled'), false)) then
    raise exception 'Haftanın Enleri henüz açık değil.';
  end if;
  if not public.owns_news(p_season_id, p_region_id) then
    raise exception 'Bu turnuvada bülten yayınlama yetkiniz yok.';
  end if;
  if p_week is null or p_week < 1 then
    raise exception 'Hafta seçilmeli.';
  end if;
  if length(trim(coalesce(p_content, ''))) = 0 then
    raise exception 'Haber metni boş olamaz.';
  end if;
  if jsonb_array_length(coalesce(p_data -> 'awards', '[]'::jsonb)) = 0
     and jsonb_array_length(coalesce(p_data -> 'eleven', '[]'::jsonb)) = 0 then
    raise exception 'Bültende en az bir seçim olmalı.';
  end if;

  select id into v_id from public.news
  where season_id = p_season_id
    and region_id is not distinct from p_region_id
    and week = p_week
    and auto_kind = 'week_awards';

  if v_id is null then
    insert into public.news (
      season_id, region_id, week, auto_kind, content,
      image_url, image_urls, auto_data, is_published
    ) values (
      p_season_id, p_region_id, p_week, 'week_awards', trim(p_content),
      v_img, case when v_img is null then '{}' else array[v_img] end,
      p_data, true
    ) returning id into v_id;
  else
    -- Yeniden yayın haberi günceller ve akışta yeniden üste taşır.
    update public.news set
      content = trim(p_content),
      image_url = v_img,
      image_urls = case when v_img is null then '{}' else array[v_img] end,
      auto_data = p_data,
      is_published = true,
      created_at = now()
    where id = v_id;
  end if;
  return v_id;
end;
$$;

revoke all on function public.publish_week_awards(uuid, uuid, int, text, text, jsonb) from public, anon;
grant execute on function public.publish_week_awards(uuid, uuid, int, text, text, jsonb) to authenticated;
