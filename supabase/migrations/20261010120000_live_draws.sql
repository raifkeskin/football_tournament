-- Canlı kura çekimi.
--
-- Kura, yönetici "canlı kurayı planla" dediği anda çekilir ve burada
-- kilitlenir (steps). Tabloya doğrudan erişim yok: izleyiciler get_live_draw
-- ile yalnızca o ana kadar açıklanmış eşleşmeleri alır; açıklama zamanları
-- (saniye) gizli değildir, takımlar zamanı gelince görünür. Süre dolunca ilk
-- get_live_draw çağrısı maçları fikstüre yazar (finalize), böylece zamanlayıcı
-- gerekmez. Haberler'de kart için news.live_draw_id kullanılır.

create table if not exists public.live_draws (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  season_id uuid not null references public.seasons(id) on delete cascade,
  group_id uuid not null references public.groups(id) on delete cascade,
  title text not null,
  start_week integer not null default 1,
  team_ids uuid[] not null,
  -- [{"w":0,"h":"<uuid>","a":"<uuid>","ht":0,"at":2.0}, ...]  (saniye, başlangıçtan)
  steps jsonb not null,
  -- [{"w":0,"t":"<uuid>"}]  bay geçen takımlar (hafta tamamlanınca görünür)
  byes jsonb not null default '[]'::jsonb,
  total_matches integer not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  status text not null default 'scheduled'
    check (status in ('scheduled', 'done', 'cancelled')),
  finalized_at timestamptz,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);

create index if not exists live_draws_group_idx on public.live_draws (group_id);
create index if not exists live_draws_league_idx on public.live_draws (league_id);

-- Doğrudan okuma/yazma yok; yalnız aşağıdaki fonksiyonlar.
alter table public.live_draws enable row level security;

alter table public.news
  add column if not exists live_draw_id uuid
  references public.live_draws(id) on delete set null;

-- Yönetici: canlı kurayı kaydeder ve haberini yayınlar (haber bildirimi
-- mevcut news_push_notify ile gider).
create or replace function public.create_live_draw(
  p_league_id uuid,
  p_season_id uuid,
  p_group_id uuid,
  p_title text,
  p_start_week integer,
  p_start_at timestamptz,
  p_team_ids uuid[],
  p_steps jsonb,
  p_byes jsonb,
  p_news_content text
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id uuid;
  v_total integer := jsonb_array_length(coalesce(p_steps, '[]'::jsonb));
  v_last numeric;
  v_start timestamptz := greatest(coalesce(p_start_at, now()), now());
begin
  if not (public.owns_league(p_league_id) or public.owns_season(p_season_id)) then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.seasons s
                 where s.id = p_season_id and s.league_id = p_league_id)
     or not exists (select 1 from public.groups g
                    where g.id = p_group_id and g.season_id = p_season_id) then
    raise exception 'Sezon / grup bu turnuvaya ait değil.';
  end if;
  if v_total = 0 then
    raise exception 'Kurada eşleşme yok.';
  end if;
  if exists (select 1 from public.matches where group_id = p_group_id) then
    raise exception 'Bu gruba maç girilmiş; kura çekilemez.';
  end if;
  if exists (select 1 from public.live_draws
             where group_id = p_group_id and status = 'scheduled') then
    raise exception 'Bu grup için planlanmış bir canlı kura zaten var.';
  end if;

  select max((s->>'at')::numeric) into v_last
  from jsonb_array_elements(p_steps) s;

  insert into public.live_draws (
    league_id, season_id, group_id, title, start_week, team_ids, steps, byes,
    total_matches, start_at, end_at
  ) values (
    p_league_id, p_season_id, p_group_id, left(trim(p_title), 160),
    greatest(coalesce(p_start_week, 1), 1), p_team_ids, p_steps,
    coalesce(p_byes, '[]'::jsonb), v_total, v_start,
    v_start + make_interval(secs => coalesce(v_last, 0) + 2)
  ) returning id into v_id;

  insert into public.news (league_id, content, is_published, live_draw_id)
  values (p_league_id, p_news_content, true, v_id);

  return v_id;
end;
$$;

-- Süresi dolan kurayı fikstüre yazar (bir kez). İçeriden çağrılır.
create or replace function public.finalize_live_draw(p_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  d public.live_draws;
begin
  select * into d from public.live_draws where id = p_id for update;
  if d.id is null or d.status <> 'scheduled' or now() < d.end_at then
    return;
  end if;
  -- Bu arada gruba elle maç girildiyse üstüne eklenmez.
  if not exists (select 1 from public.matches where group_id = d.group_id) then
    insert into public.matches (
      league_id, season_id, group_id, home_team_id, away_team_id,
      home_score, away_score, week, status
    )
    select d.league_id, d.season_id, d.group_id,
           (s->>'h')::uuid, (s->>'a')::uuid, 0, 0,
           d.start_week + (s->>'w')::integer, 'notStarted'
    from jsonb_array_elements(d.steps) s;
  end if;
  update public.live_draws
  set status = 'done', finalized_at = now()
  where id = p_id;
end;
$$;

-- İzleyici: kuranın o anki hali. Açıklanmamış takımlar dönmez.
create or replace function public.get_live_draw(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  d public.live_draws;
  v_elapsed numeric;
  v_revealed jsonb;
  v_current jsonb;
  v_byes jsonb;
  v_next numeric;
begin
  select * into d from public.live_draws where id = p_id;
  if d.id is null or not public.can_view_league(d.league_id) then
    return null;
  end if;
  if d.status = 'scheduled' and now() >= d.end_at then
    perform public.finalize_live_draw(p_id);
    select * into d from public.live_draws where id = p_id;
  end if;

  v_elapsed := extract(epoch from (now() - d.start_at));

  if d.status = 'cancelled' then
    v_revealed := '[]'::jsonb;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
             'w', (s->>'w')::int, 'h', s->>'h', 'a', s->>'a') order by ord), '[]'::jsonb)
    into v_revealed
    from jsonb_array_elements(d.steps) with ordinality as x(s, ord)
    where d.status = 'done' or (s->>'at')::numeric <= v_elapsed;

    -- Ev sahibi açıklanmış, rakip bekleniyor.
    select jsonb_build_object('w', (s->>'w')::int, 'h', s->>'h')
    into v_current
    from jsonb_array_elements(d.steps) s
    where d.status = 'scheduled'
      and (s->>'ht')::numeric <= v_elapsed
      and (s->>'at')::numeric > v_elapsed
    limit 1;

    -- Bay: haftanın son eşleşmesi açıklanınca.
    select coalesce(jsonb_agg(b), '[]'::jsonb) into v_byes
    from jsonb_array_elements(d.byes) b
    where d.status = 'done' or exists (
      select 1 from jsonb_array_elements(d.steps) s
      where (s->>'w')::int = (b->>'w')::int
    ) and not exists (
      select 1 from jsonb_array_elements(d.steps) s
      where (s->>'w')::int = (b->>'w')::int
        and (s->>'at')::numeric > v_elapsed
    );

    -- Bir sonraki açıklama anı (istemci o an yeniden sorar).
    select min(t) into v_next from (
      select (s->>'ht')::numeric t from jsonb_array_elements(d.steps) s
      union all
      select (s->>'at')::numeric from jsonb_array_elements(d.steps) s
    ) z where t > v_elapsed;
  end if;

  return jsonb_build_object(
    'id', d.id,
    'league_id', d.league_id,
    'season_id', d.season_id,
    'title', d.title,
    'start_week', d.start_week,
    'team_ids', to_jsonb(d.team_ids),
    'total', d.total_matches,
    'start_at', d.start_at,
    'end_at', d.end_at,
    'status', d.status,
    'server_now', now(),
    'revealed', v_revealed,
    'current', v_current,
    'byes', coalesce(v_byes, '[]'::jsonb),
    'next_in', case when v_next is null then null else v_next - v_elapsed end
  );
end;
$$;

-- Yönetici: başlamadan iptal (haber de yayından kalkar).
create or replace function public.cancel_live_draw(p_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  d public.live_draws;
begin
  select * into d from public.live_draws where id = p_id;
  if d.id is null then
    return;
  end if;
  if not (public.owns_league(d.league_id) or public.owns_season(d.season_id)) then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  if d.status <> 'scheduled' or now() >= d.start_at then
    raise exception 'Başlamış kura iptal edilemez.';
  end if;
  update public.live_draws set status = 'cancelled' where id = p_id;
  update public.news set is_published = false where live_draw_id = p_id;
end;
$$;

-- Yönetici ekranı: gruptaki planlı kura (varsa) ve süresi dolanları yazma.
create or replace function public.live_draw_for_group(p_group_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id uuid;
begin
  select id into v_id from public.live_draws
  where group_id = p_group_id and status <> 'cancelled'
  order by created_at desc limit 1;
  if v_id is null then
    return null;
  end if;
  return public.get_live_draw(v_id);
end;
$$;

revoke all on function public.finalize_live_draw(uuid) from public, anon, authenticated;
grant execute on function public.create_live_draw(uuid, uuid, uuid, text, integer, timestamptz, uuid[], jsonb, jsonb, text) to authenticated;
grant execute on function public.get_live_draw(uuid) to anon, authenticated;
grant execute on function public.cancel_live_draw(uuid) to authenticated;
grant execute on function public.live_draw_for_group(uuid) to authenticated;
