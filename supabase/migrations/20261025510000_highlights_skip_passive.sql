-- Pasif turnuvada yapay zekâ taraması çalışmaz (otomatik tarama uygunluğu).
CREATE OR REPLACE FUNCTION public.highlights_auto_eligible(p_match_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
      from public.matches m
      join public.seasons s on s.id = m.season_id
      join public.leagues l on l.id = m.league_id
     where m.id = p_match_id
       -- Pasif turnuvada otomatik tarama yok.
       and coalesce(l.status, '') <> 'passive'
       and l.is_active is not false
       and m.status = 'finished'
       and m.deleted_at is null
       and m.updated_at > now() - interval '12 hours'
       and s.ai_clips_enabled is not false
       and not public.is_demo_league(m.league_id)
       and coalesce(m.home_score, 0) + coalesce(m.away_score, 0) > 0
       and exists (
         select 1 from public.match_media mm
          where mm.match_id = m.id and mm.media_type = 'Maç Yayın Linki'
            and mm.url ~* '(youtube\.com|youtu\.be)')
       and (select count(*) from public.match_events e
             where e.match_id = m.id and e.event_type = 'goal')
           = coalesce(m.home_score, 0) + coalesce(m.away_score, 0)
       and not exists (
         select 1 from public.match_events e
          where e.match_id = m.id and e.event_type = 'goal' and e.minute is null)
  )
$function$;
