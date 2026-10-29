-- Otomatik maç sonucu haberi: iki takımın takım fotoğrafı haberin
-- görselleri olur; kazananınki önce, beraberlikte maça göre sabit rastgele
-- sıra (her güncellemede yer değiştirmesin). Takım fotoğrafı maç bittikten
-- sonra yüklenince / silinince haber kendiliğinden güncellenir.

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
             when m.hs > m.aws then (p.team_id = m.home_team_id)::int
             when m.aws > m.hs then (p.team_id = m.away_team_id)::int
             else 0
           end desc,
           md5(m.id::text || p.team_id::text)), '{}')
    from photos p cross join m
   where p.team_id in (m.home_team_id, m.away_team_id)
$function$;
revoke all on function public.result_news_photos(uuid) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.refresh_result_news(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  m record;
  v_region uuid;
  v_enabled boolean;
  v_data jsonb;
  v_id uuid;
  v_published boolean;
begin
  select * into m from public.matches where id = p_match_id;
  if not found or m.season_id is null then
    return;
  end if;
  select g.region_id into v_region from public.groups g where g.id = m.group_id;
  select l.auto_result_news into v_enabled
    from public.seasons s join public.leagues l on l.id = s.league_id
   where s.id = m.season_id;

  select id, is_published into v_id, v_published
    from public.news
   where auto_kind = 'match_result' and match_id = p_match_id;

  if m.status = 'finished' and m.deleted_at is null then
    v_data := public.match_result_data(p_match_id);
    if v_id is null then
      if coalesce(v_enabled, true) then
        insert into public.news (season_id, region_id, content, is_published,
                                 auto_kind, match_id, week, auto_data,
                                 image_urls)
        values (m.season_id, v_region, public.result_text(v_data), true,
                'match_result', p_match_id, m.week, v_data,
                public.result_news_photos(p_match_id));
      end if;
    else
      update public.news
         set content = public.result_text(v_data),
             auto_data = v_data,
             image_urls = public.result_news_photos(p_match_id),
             week = m.week,
             region_id = v_region,
             is_published = case when auto_hidden then true else is_published end,
             auto_hidden = false
       where id = v_id;
    end if;
  elsif v_id is not null and v_published then
    update public.news set is_published = false, auto_hidden = true
     where id = v_id;
  end if;

  perform public.refresh_week_results_news(m.season_id, v_region, m.week);
end;
$function$

;

create or replace function public.match_media_result_news()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match uuid := coalesce(new.match_id, old.match_id);
begin
  if coalesce(new.media_type, old.media_type) = 'Takım Fotosu' then
    begin
      update public.news
         set image_urls = public.result_news_photos(v_match)
       where auto_kind = 'match_result' and match_id = v_match;
    exception when others then
      raise warning 'match_media_result_news: %', sqlerrm;
    end;
  end if;
  return null;
end;
$function$;
drop trigger if exists match_media_result_news on public.match_media;
create trigger match_media_result_news
  after insert or update or delete on public.match_media
  for each row execute function public.match_media_result_news();

-- Mevcut sonuç haberlerine de fotoğraflar.
update public.news n
   set image_urls = public.result_news_photos(n.match_id)
 where n.auto_kind = 'match_result' and n.match_id is not null
   and cardinality(public.result_news_photos(n.match_id)) > 0;
