-- Turnuva videoları ve maç röportajları (Instagram gönderisi / Reels
-- bağlantısı; video Instagram'da kalır, uygulamada gömülü oynatılır).
--   videos.kind: 'tournament' (açılış, tanıtım…; maçtan bağımsız) ya da maç
--   röportajı 'pre' (maç öncesi) / 'live' (maç anı) / 'post' (maç sonrası).
--   Röportajlar maç + tür başına tek habere ('interviews') toplanır; sonradan
--   eklenen bağlantı aynı habere girer. Turnuva videosu isterse kendi
--   haberini ('video') açar.
-- Ekleme / silme: admin, kurucu başkan, o sezonda bölge sorumlusu.
-- Haberler: news.pinned_at ile turnuva başına en çok 3 haber sabitlenir.

create table if not exists public.videos (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete cascade,
  match_id uuid references public.matches(id) on delete cascade,
  kind text not null check (kind in ('tournament', 'pre', 'live', 'post')),
  team_id uuid references public.teams(id) on delete set null,
  title text,
  url text not null,
  code text not null,
  pinned boolean not null default false,
  news_id uuid references public.news(id) on delete set null,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique (season_id, code),
  check ((kind = 'tournament') = (match_id is null))
);
create index if not exists videos_match_idx on public.videos (match_id);
alter table public.videos enable row level security;

drop policy if exists videos_read on public.videos;
create policy videos_read on public.videos for select
  using (public.can_view_season(season_id));

alter table public.news add column if not exists pinned_at timestamptz;

alter table public.news drop constraint if exists news_auto_kind_check;
alter table public.news add constraint news_auto_kind_check check (auto_kind = any (array[
  'match_result', 'week_results', 'instagram', 'match_preview', 'day_preview',
  'goal_of_week', 'player_of_week', 'team_of_week', 'week_awards',
  'interviews', 'video']));
create unique index if not exists news_interviews_uq on public.news
  (match_id, (auto_data ->> 'kind')) where auto_kind = 'interviews';

-- Sezonun medyasını yönetebilir mi: admin, kurucu başkan, bölge sorumlusu.
create or replace function public.can_manage_season_media(p_season uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.owns_season(p_season) or exists (
    select 1 from public.season_regions r
    join public.region_owners ro on ro.region_id = r.id
    where r.season_id = p_season and ro.user_id = auth.uid()
  )
$$;

-- Maçın röportaj haberini videolardan yeniden kurar (yoksa açar, video
-- kalmadıysa siler). Eski sürümler haberi kapak + Instagram bağlantısıyla
-- düz haber gibi gösterir.
create or replace function public._interview_news_sync(p_match uuid, p_kind text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  m record;
  v_list jsonb;
  v_first text;
  v_news uuid;
  v_label text := case p_kind when 'pre' then 'maç öncesi'
                              when 'live' then 'maç anı'
                              else 'maç sonrası' end;
  v_text text;
begin
  select mt.id, mt.season_id, mt.week,
         ht.id as home_id, ht.name as home, ht.logo_url as home_logo,
         at.id as away_id, at.name as away, at.logo_url as away_logo
    into m
    from public.matches mt
    join public.teams ht on ht.id = mt.home_team_id
    join public.teams at on at.id = mt.away_team_id
   where mt.id = p_match;
  if m.id is null then return; end if;

  select jsonb_agg(jsonb_build_object(
           'id', v.id, 'url', v.url, 'code', v.code, 'title', v.title,
           'team_id', v.team_id, 'team', t.name, 'team_logo', t.logo_url)
         order by v.created_at),
         (array_agg(v.url order by v.created_at))[1]
    into v_list, v_first
    from public.videos v
    left join public.teams t on t.id = v.team_id
   where v.match_id = p_match and v.kind = p_kind;

  select id into v_news from public.news
   where auto_kind = 'interviews' and match_id = p_match
     and auto_data ->> 'kind' = p_kind
   limit 1;

  if v_list is null then
    if v_news is not null then
      delete from public.news where id = v_news;
    end if;
    return;
  end if;

  v_text := format('%s – %s: %s röportajları', m.home, m.away, v_label);
  if v_news is null then
    insert into public.news (season_id, week, match_id, auto_kind, content,
                             link_url, auto_data, is_published)
    values (m.season_id, m.week, p_match, 'interviews', v_text, v_first,
            jsonb_build_object(
              'kind', p_kind, 'home', m.home, 'away', m.away,
              'home_id', m.home_id, 'away_id', m.away_id,
              'home_logo', m.home_logo, 'away_logo', m.away_logo,
              'videos', v_list),
            true)
    returning id into v_news;
  else
    update public.news set
      link_url = v_first,
      auto_data = coalesce(auto_data, '{}'::jsonb) || jsonb_build_object('videos', v_list)
     where id = v_news;
  end if;
  update public.videos set news_id = v_news
   where match_id = p_match and kind = p_kind
     and news_id is distinct from v_news;
end;
$$;
revoke all on function public._interview_news_sync(uuid, text) from public, anon, authenticated;

-- Video ekler. Bağlantı Instagram gönderisi / Reels olmalı (hikâye olmaz).
create or replace function public.video_add(
  p_season uuid,
  p_match uuid,
  p_kind text,
  p_team uuid,
  p_title text,
  p_url text,
  p_pinned boolean default false,
  p_as_news boolean default false
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_m text[];
  v_code text;
  v_url text;
  v_id uuid;
  v_news uuid;
  v_season uuid := p_season;
begin
  if p_match is not null then
    select season_id into v_season from public.matches where id = p_match;
  end if;
  if v_season is null or not public.can_manage_season_media(v_season) then
    raise exception 'Yetkiniz yok.';
  end if;
  if p_kind not in ('tournament', 'pre', 'live', 'post')
     or ((p_kind = 'tournament') <> (p_match is null)) then
    raise exception 'Geçersiz video türü.';
  end if;
  if coalesce(p_url, '') ~* 'instagram\.com/stories/' then
    raise exception 'Hikâyeler eklenemez; gönderi ya da Reels bağlantısı kullanın.';
  end if;
  v_m := regexp_match(coalesce(p_url, ''),
    'instagram\.com/(?:[A-Za-z0-9_.]+/)?(p|reel|reels|tv)/([A-Za-z0-9_-]+)', 'i');
  if v_m is null then
    raise exception 'Instagram gönderisi ya da Reels bağlantısı yapıştırın.';
  end if;
  v_code := v_m[2];
  v_url := format('https://www.instagram.com/%s/%s/',
                  case when lower(v_m[1]) = 'p' then 'p' else 'reel' end, v_code);
  if exists (select 1 from public.videos where season_id = v_season and code = v_code) then
    raise exception 'Bu video zaten ekli.';
  end if;
  if p_match is not null and (
       select count(*) from public.videos where match_id = p_match and kind = p_kind
     ) >= 4 then
    raise exception 'Bu türde en çok 4 video eklenebilir.';
  end if;

  insert into public.videos (season_id, match_id, kind, team_id, title, url, code, pinned)
  values (v_season, p_match, p_kind, p_team, nullif(trim(coalesce(p_title, '')), ''),
          v_url, v_code, coalesce(p_pinned, false))
  returning id into v_id;

  if p_match is not null then
    perform public._interview_news_sync(p_match, p_kind);
  elsif coalesce(p_as_news, false) then
    insert into public.news (season_id, auto_kind, content, link_url, auto_data, is_published)
    values (v_season, 'video', coalesce(nullif(trim(coalesce(p_title, '')), ''), 'Turnuva videosu'),
            v_url,
            jsonb_build_object('title', nullif(trim(coalesce(p_title, '')), ''),
              'videos', jsonb_build_array(jsonb_build_object(
                'id', v_id, 'url', v_url, 'code', v_code, 'title', p_title))),
            true)
    returning id into v_news;
    update public.videos set news_id = v_news where id = v_id;
  end if;
  return v_id;
end;
$$;
revoke all on function public.video_add(uuid, uuid, text, uuid, text, text, boolean, boolean) from public, anon;
grant execute on function public.video_add(uuid, uuid, text, uuid, text, text, boolean, boolean) to authenticated;

create or replace function public.video_delete(p_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v record;
begin
  select * into v from public.videos where id = p_id;
  if v.id is null then return; end if;
  if not public.can_manage_season_media(v.season_id) then
    raise exception 'Yetkiniz yok.';
  end if;
  delete from public.videos where id = p_id;
  if v.match_id is not null then
    perform public._interview_news_sync(v.match_id, v.kind);
  elsif v.news_id is not null then
    delete from public.news where id = v.news_id and auto_kind = 'video';
  end if;
end;
$$;
revoke all on function public.video_delete(uuid) from public, anon;
grant execute on function public.video_delete(uuid) to authenticated;

create or replace function public.video_set_pinned(p_id uuid, p_pinned boolean)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_season uuid;
begin
  select season_id into v_season from public.videos where id = p_id;
  if v_season is null or not public.can_manage_season_media(v_season) then
    raise exception 'Yetkiniz yok.';
  end if;
  update public.videos set pinned = coalesce(p_pinned, false) where id = p_id;
end;
$$;
revoke all on function public.video_set_pinned(uuid, boolean) from public, anon;
grant execute on function public.video_set_pinned(uuid, boolean) to authenticated;

-- Haberi turnuvanın haber akışında en üste sabitler (turnuva başına en çok 3).
create or replace function public.news_set_pinned(p_news uuid, p_pinned boolean)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  n record;
  v_league uuid;
begin
  select id, season_id, region_id into n from public.news where id = p_news;
  if n.id is null then return; end if;
  if not (public.owns_news(n.season_id, n.region_id)
          or public.can_manage_season_media(n.season_id)) then
    raise exception 'Yetkiniz yok.';
  end if;
  if not coalesce(p_pinned, false) then
    update public.news set pinned_at = null where id = p_news;
    return;
  end if;
  select league_id into v_league from public.seasons where id = n.season_id;
  if (select count(*) from public.news x
        join public.seasons s on s.id = x.season_id
       where s.league_id = v_league and x.pinned_at is not null and x.id <> p_news) >= 3 then
    raise exception 'En çok 3 haber sabitlenebilir; önce birinin sabitlemesini kaldırın.';
  end if;
  update public.news set pinned_at = now() where id = p_news;
end;
$$;
revoke all on function public.news_set_pinned(uuid, boolean) from public, anon;
grant execute on function public.news_set_pinned(uuid, boolean) to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.videos;
exception when duplicate_object then null; when undefined_object then null;
end $$;
