-- Sezonun Enleri anketi (1. aşama: veri ve RPC'ler). Yalnız admin hazırlar;
-- sezonun oynanacak lig maçı kalmadan açılamaz. Adaylar yayınlanmış Haftanın
-- Enleri bültenlerinden (news.auto_data.awards) toplanır; admin elle gol ekler.
-- Kullanıcı kategori başına 1 oy kullanır, kendine oy veremez.

insert into public.app_settings (key, value)
values ('season_awards_enabled', 'false'::jsonb)
on conflict (key) do nothing;

create table if not exists public.season_award_polls (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete cascade,
  region_id uuid,
  closes_at timestamptz not null,
  status text not null default 'open' check (status in ('open', 'closed', 'published')),
  news_id uuid,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create unique index if not exists season_award_polls_one
  on public.season_award_polls (season_id, coalesce(region_id, '00000000-0000-0000-0000-000000000000'::uuid));

create table if not exists public.season_award_candidates (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.season_award_polls(id) on delete cascade,
  category text not null check (category in ('player', 'keeper', 'goal', 'team', 'match', 'fair')),
  source text not null default 'week' check (source in ('week', 'manual')),
  week int,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists season_award_candidates_poll on public.season_award_candidates (poll_id, category);

create table if not exists public.season_award_votes (
  poll_id uuid not null references public.season_award_polls(id) on delete cascade,
  category text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  candidate_id uuid not null references public.season_award_candidates(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (poll_id, category, user_id)
);
alter table public.season_award_polls enable row level security;
alter table public.season_award_candidates enable row level security;
alter table public.season_award_votes enable row level security;
-- Doğrudan erişim yok; yalnız aşağıdaki security definer işlevler.

-- Sezon tamamlandı: biten maç var ve oynanacak lig maçı kalmadı (kupa/playoff hariç).
create or replace function public.season_awards_ready(p_season_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.matches m
                 where m.season_id = p_season_id and m.deleted_at is null
                   and m.status = 'finished')
     and not exists (select 1 from public.matches m
                 where m.season_id = p_season_id and m.deleted_at is null
                   and m.cup_bracket_id is null and m.cup_stage is null
                   and m.status not in ('finished', 'cancelled'))
$$;

-- Haftanın Enleri bültenlerinden aday havuzu (kategori başına).
create or replace function public.season_award_pool(p_season_id uuid, p_region_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Yetkiniz yok.'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'category', a.kind, 'week', n.week, 'data', a.item)
           order by a.kind, n.week)
    from public.news n
    cross join lateral (
      select x ->> 'kind' as kind, x as item
      from jsonb_array_elements(coalesce(n.auto_data -> 'awards', '[]'::jsonb)) x
    ) a
    where n.season_id = p_season_id
      and n.auto_kind = 'week_awards'
      and n.is_published
      and (p_region_id is null or n.region_id is not distinct from p_region_id)
      and a.kind in ('player', 'keeper', 'goal', 'team', 'match', 'fair')
  ), '[]'::jsonb);
end $$;

-- Elle gol ekleme araması: oyuncu ya da takım adı; isteğe bağlı hafta.
create or replace function public.season_goal_search(p_season_id uuid, p_q text default '', p_week int default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare q text := public.norm_person_name(coalesce(p_q, ''));
begin
  if not public.is_admin() then raise exception 'Yetkiniz yok.'; end if;
  return coalesce((
    select jsonb_agg(r order by (r ->> 'week')::int, (r ->> 'minute')::int)
    from (
      select jsonb_build_object(
               'event_id', e.id, 'match_id', m.id, 'week', m.week, 'minute', e.minute,
               'player', jsonb_build_object('id', p.id, 'name', trim(p.name || ' ' || coalesce(p.surname, '')), 'photo', coalesce(p.photo_url, '')),
               'team', jsonb_build_object('id', t.id, 'name', t.name, 'logo', coalesce(t.logo_url, '')),
               'match', jsonb_build_object('id', m.id, 'hs', m.home_score, 'as', m.away_score,
                          'home', (select jsonb_build_object('id', h.id, 'name', h.name) from public.teams h where h.id = m.home_team_id),
                          'away', (select jsonb_build_object('id', w.id, 'name', w.name) from public.teams w where w.id = m.away_team_id)),
               'instagram_url', (select (a.x ->> 'instagram_url')
                                 from public.news n
                                 cross join lateral jsonb_array_elements(coalesce(n.auto_data -> 'awards', '[]'::jsonb)) a(x)
                                 where n.season_id = p_season_id and n.auto_kind = 'week_awards'
                                   and a.x ->> 'kind' = 'goal'
                                   and a.x #>> '{player,id}' = p.id::text
                                   and a.x #>> '{match,id}' = m.id::text
                                 limit 1)
             ) as r
      from public.match_events e
      join public.matches m on m.id = e.match_id
      join public.players p on p.id = e.player_id
      join public.teams t on t.id = e.team_id
      where e.event_type = 'goal' and coalesce(e.is_own_goal, false) = false
        and m.season_id = p_season_id and m.deleted_at is null
        and (p_week is null or m.week = p_week)
        and (q = '' or public.norm_person_name(p.name || ' ' || coalesce(p.surname, '')) like '%' || q || '%'
             or public.norm_person_name(t.name) like '%' || q || '%')
      limit 60
    ) s
  ), '[]'::jsonb);
end $$;

-- Anketi oluşturur: sezon tamamlanmış olmalı; adaylar jsonb dizisi
-- [{category, source, week, data}].
create or replace function public.season_award_create(p_season_id uuid, p_region_id uuid, p_closes_at timestamptz, p_candidates jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid; c jsonb;
begin
  if not public.is_admin() then raise exception 'Yetkiniz yok.'; end if;
  if not public.season_awards_ready(p_season_id) then
    raise exception 'Sezon henüz tamamlanmadı; Sezonun Enleri anketi açılamaz.';
  end if;
  if p_closes_at <= now() then raise exception 'Bitiş zamanı gelecekte olmalı.'; end if;
  if jsonb_array_length(coalesce(p_candidates, '[]'::jsonb)) = 0 then
    raise exception 'En az bir aday gerekli.';
  end if;
  insert into public.season_award_polls (season_id, region_id, closes_at)
  values (p_season_id, p_region_id, p_closes_at)
  returning id into v_id;
  for c in select * from jsonb_array_elements(p_candidates) loop
    insert into public.season_award_candidates (poll_id, category, source, week, data)
    values (v_id, c ->> 'category', coalesce(c ->> 'source', 'week'),
            nullif(c ->> 'week', '')::int, coalesce(c -> 'data', '{}'::jsonb));
  end loop;
  return v_id;
end $$;

-- Oy (kategori başına 1; süre bitene dek değiştirilebilir). Kendine oy yok.
create or replace function public.season_award_vote(p_poll_id uuid, p_candidate_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare pl public.season_award_polls; cd public.season_award_candidates; v_player uuid;
begin
  if auth.uid() is null then raise exception 'Oy için giriş yapın.'; end if;
  select * into pl from public.season_award_polls where id = p_poll_id;
  if pl.id is null or pl.status <> 'open' or pl.closes_at <= now() then
    raise exception 'Bu anket kapalı.';
  end if;
  select * into cd from public.season_award_candidates where id = p_candidate_id and poll_id = p_poll_id;
  if cd.id is null then raise exception 'Aday bulunamadı.'; end if;
  v_player := nullif(cd.data #>> '{player,id}', '')::uuid;
  if v_player is not null and exists (
       select 1 from public.players p where p.id = v_player and p.auth_uid = auth.uid()) then
    raise exception 'Kendinize oy veremezsiniz.';
  end if;
  insert into public.season_award_votes (poll_id, category, user_id, candidate_id)
  values (p_poll_id, cd.category, auth.uid(), p_candidate_id)
  on conflict (poll_id, category, user_id) do update set candidate_id = excluded.candidate_id, created_at = now();
end $$;

-- Anket + adaylar + benim oyum; sayılar yalnız kapanınca (ya da admin için) görünür.
create or replace function public.season_award_get(p_poll_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare pl public.season_award_polls; show boolean;
begin
  select * into pl from public.season_award_polls where id = p_poll_id;
  if pl.id is null then return null; end if;
  show := public.is_admin() or pl.status <> 'open' or pl.closes_at <= now();
  return jsonb_build_object(
    'id', pl.id, 'season_id', pl.season_id, 'status', pl.status,
    'closes_at', pl.closes_at, 'is_open', pl.status = 'open' and pl.closes_at > now(),
    'counts_visible', show,
    'candidates', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id, 'category', c.category, 'source', c.source, 'week', c.week, 'data', c.data,
               'votes', case when show then (select count(*) from public.season_award_votes v where v.candidate_id = c.id) end,
               'mine', exists (select 1 from public.season_award_votes v
                               where v.candidate_id = c.id and v.user_id = auth.uid()))
             order by c.category, c.week)
      from public.season_award_candidates c where c.poll_id = pl.id), '[]'::jsonb));
end $$;

create or replace function public.season_award_close(p_poll_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Yetkiniz yok.'; end if;
  update public.season_award_polls set status = 'closed', closes_at = least(closes_at, now())
  where id = p_poll_id and status = 'open';
end $$;

revoke all on function public.season_awards_ready(uuid) from public, anon;
revoke all on function public.season_award_pool(uuid, uuid) from public, anon;
revoke all on function public.season_goal_search(uuid, text, int) from public, anon;
revoke all on function public.season_award_create(uuid, uuid, timestamptz, jsonb) from public, anon;
revoke all on function public.season_award_vote(uuid, uuid) from public, anon;
revoke all on function public.season_award_get(uuid) from public, anon;
revoke all on function public.season_award_close(uuid) from public, anon;
grant execute on function public.season_awards_ready(uuid) to authenticated;
grant execute on function public.season_award_pool(uuid, uuid) to authenticated;
grant execute on function public.season_goal_search(uuid, text, int) to authenticated;
grant execute on function public.season_award_create(uuid, uuid, timestamptz, jsonb) to authenticated;
grant execute on function public.season_award_vote(uuid, uuid) to authenticated;
grant execute on function public.season_award_get(uuid) to authenticated;
grant execute on function public.season_award_close(uuid) to authenticated;
