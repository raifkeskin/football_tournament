-- Turnuvanın sosyal medya / web adresleri (yan menüde turnuva adının
-- altında simge olarak; ileride Instagram paylaşımı için de). Sezonda
-- tutulan eski Instagram / YouTube adresleri turnuvaya taşınır.

alter table public.leagues
  add column if not exists instagram_url text,
  add column if not exists facebook_url text,
  add column if not exists youtube_url text,
  add column if not exists website_url text;

update public.leagues l
   set instagram_url = coalesce(l.instagram_url, s.instagram_url),
       youtube_url = coalesce(l.youtube_url, s.youtube_url)
  from (
    select distinct on (league_id) league_id,
           nullif(trim(instagram_url), '') as instagram_url,
           nullif(trim(youtube_url), '') as youtube_url
    from public.seasons
    order by league_id, is_active desc, start_date desc nulls last
  ) s
 where s.league_id = l.id
   and (s.instagram_url is not null or s.youtube_url is not null);
