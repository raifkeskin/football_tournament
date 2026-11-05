-- Video kapak fotoğrafı (isteğe bağlı). Kapak yoksa turnuva videosunda
-- turnuva logosu gösterilir; bunun için haber verisine 'logo' eklenir.
--   videos.cover_url, video_add(..., p_cover), video_set_cover.
-- Kapak 'news' klasörüne yüklenir; bölge sorumlusu da (video ekleyebildiği
-- için) bu klasöre yükleyebilir.

alter table public.videos add column if not exists cover_url text;

create or replace function public._video_json(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select jsonb_build_object(
           'id', v.id, 'url', v.url, 'code', v.code, 'title', v.title,
           'cover', v.cover_url,
           'team_id', v.team_id, 'team', t.name, 'team_logo', t.logo_url)
    from public.videos v
    left join public.teams t on t.id = v.team_id
   where v.id = p_id
$$;
revoke all on function public._video_json(uuid) from public, anon, authenticated;

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
         at.id as away_id, at.name as away, at.logo_url as away_logo,
         l.logo_url as league_logo
    into m
    from public.matches mt
    join public.teams ht on ht.id = mt.home_team_id
    join public.teams at on at.id = mt.away_team_id
    left join public.seasons s on s.id = mt.season_id
    left join public.leagues l on l.id = s.league_id
   where mt.id = p_match;
  if m.id is null then return; end if;

  select jsonb_agg(public._video_json(v.id) order by v.created_at),
         (array_agg(v.url order by v.created_at))[1]
    into v_list, v_first
    from public.videos v
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
              'logo', m.league_logo,
              'videos', v_list),
            true)
    returning id into v_news;
  else
    update public.news set
      link_url = v_first,
      auto_data = coalesce(auto_data, '{}'::jsonb)
                  || jsonb_build_object('videos', v_list, 'logo', m.league_logo)
     where id = v_news;
  end if;
  update public.videos set news_id = v_news
   where match_id = p_match and kind = p_kind
     and news_id is distinct from v_news;
end;
$$;
revoke all on function public._interview_news_sync(uuid, text) from public, anon, authenticated;

drop function if exists public.video_add(uuid, uuid, text, uuid, text, text, boolean, boolean);
create or replace function public.video_add(
  p_season uuid,
  p_match uuid,
  p_kind text,
  p_team uuid,
  p_title text,
  p_url text,
  p_pinned boolean default false,
  p_as_news boolean default false,
  p_cover text default null
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
  v_logo text;
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

  insert into public.videos (season_id, match_id, kind, team_id, title, url, code,
                             pinned, cover_url)
  values (v_season, p_match, p_kind, p_team, nullif(trim(coalesce(p_title, '')), ''),
          v_url, v_code, coalesce(p_pinned, false),
          nullif(trim(coalesce(p_cover, '')), ''))
  returning id into v_id;

  if p_match is not null then
    perform public._interview_news_sync(p_match, p_kind);
  elsif coalesce(p_as_news, false) then
    select l.logo_url into v_logo
      from public.seasons s join public.leagues l on l.id = s.league_id
     where s.id = v_season;
    insert into public.news (season_id, auto_kind, content, link_url, auto_data, is_published)
    values (v_season, 'video', coalesce(nullif(trim(coalesce(p_title, '')), ''), 'Turnuva videosu'),
            v_url,
            jsonb_build_object('title', nullif(trim(coalesce(p_title, '')), ''),
              'logo', v_logo,
              'videos', jsonb_build_array(public._video_json(v_id))),
            true)
    returning id into v_news;
    update public.videos set news_id = v_news where id = v_id;
  end if;
  return v_id;
end;
$$;
revoke all on function public.video_add(uuid, uuid, text, uuid, text, text, boolean, boolean, text) from public, anon;
grant execute on function public.video_add(uuid, uuid, text, uuid, text, text, boolean, boolean, text) to authenticated;

-- Kapak fotoğrafını değiştirir / kaldırır (null); haberi de günceller.
create or replace function public.video_set_cover(p_id uuid, p_cover text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v record;
begin
  select * into v from public.videos where id = p_id;
  if v.id is null or not public.can_manage_season_media(v.season_id) then
    raise exception 'Yetkiniz yok.';
  end if;
  update public.videos set cover_url = nullif(trim(coalesce(p_cover, '')), '')
   where id = p_id;
  if v.match_id is not null then
    perform public._interview_news_sync(v.match_id, v.kind);
  elsif v.news_id is not null then
    update public.news
       set auto_data = coalesce(auto_data, '{}'::jsonb)
                       || jsonb_build_object('videos', jsonb_build_array(public._video_json(p_id)))
     where id = v.news_id and auto_kind = 'video';
  end if;
end;
$$;
revoke all on function public.video_set_cover(uuid, text) from public, anon;
grant execute on function public.video_set_cover(uuid, text) to authenticated;

-- Mevcut haberlere turnuva logosu.
update public.news n
   set auto_data = n.auto_data || jsonb_build_object('logo', l.logo_url)
  from public.seasons s
  join public.leagues l on l.id = s.league_id
 where n.auto_kind in ('interviews', 'video')
   and s.id = n.season_id
   and l.logo_url is not null;

create or replace function public.can_upload_media(p_folder text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select
    (p_folder = 'posters' and (public.is_admin() or public.is_any_league_owner()))
    or (
      p_folder in ('leagues', 'teams', 'players', 'news', 'matches', 'sponsors')
      and (
        public.is_admin()
        or public.is_any_league_owner()
        or (
          p_folder = 'players'
          and exists (select 1 from public.team_managers where user_id = auth.uid())
        )
        or (p_folder = 'news' and public.is_any_region_owner())
      )
    )
$$;
