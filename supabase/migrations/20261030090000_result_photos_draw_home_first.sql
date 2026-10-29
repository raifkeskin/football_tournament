-- Sonuç haberi fotoğrafları: kazananınki önce; beraberlikte önce ev sahibi.

create or replace function public.result_news_photos(p_match_id uuid)
returns text[]
language sql
stable
security definer
set search_path to ''
as $function$
  with m as (
    select id, home_team_id, away_team_id,
           coalesce(home_score, 0) hs, coalesce(away_score, 0) aws
      from public.matches where id = p_match_id
  ), photos as (
    select distinct on (mm.team_id) mm.team_id, mm.url
      from public.match_media mm
     where mm.match_id = p_match_id
       and mm.media_type = 'Takım Fotosu'
       and mm.team_id is not null
       and coalesce(trim(mm.url), '') <> ''
     order by mm.team_id, mm.created_at desc
  )
  select coalesce(array_agg(p.url order by
           case
             when m.aws > m.hs then (p.team_id = m.away_team_id)::int
             else (p.team_id = m.home_team_id)::int
           end desc), '{}')
    from photos p cross join m
   where p.team_id in (m.home_team_id, m.away_team_id)
$function$;
revoke all on function public.result_news_photos(uuid) from public, anon, authenticated;

update public.news n
   set image_urls = public.result_news_photos(n.match_id)
 where n.auto_kind = 'match_result' and n.match_id is not null
   and n.image_urls is distinct from public.result_news_photos(n.match_id);
